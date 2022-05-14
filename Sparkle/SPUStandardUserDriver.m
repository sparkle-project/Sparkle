//
//  SPUStandardUserDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/14/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import "SPUStandardUserDriver.h"
#import "SPUStandardUserDriverDelegate.h"
#import "SUAppcastItem.h"
#import "SUVersionDisplayProtocol.h"
#import "SUHost.h"
#import "SUUpdatePermissionPrompt.h"
#import "SUStatusController.h"
#import "SUUpdateAlert.h"
#import "SULocalizations.h"
#import "SUApplicationInfo.h"
#import "SUOperatingSystem.h"
#import "SPUUserUpdateState.h"
#import "SUErrors.h"
#import "SPUInstallationType.h"
#import "SULog.h"
#include <time.h>


#import <AppKit/AppKit.h>

// The amount of time we wait until the app becomes inactive and active again to show an update prompt at an opportune time.
static const NSTimeInterval SUScheduledUpdateActiveAppLeewayInterval = DEBUG ? 60.0 * 2 : 30 * 60.0;
// The amount of time the app is allowed to be idle for us to consider showing an update prompt right away when the app is active
static const NSTimeInterval SUScheduledUpdateIdleEventLeewayInterval = DEBUG ? 30.0 : 5 * 60.0;

@interface SPUStandardUserDriver ()

@property (nonatomic, readonly) SUHost *host;
// We must store the oldHostName before the host is potentially replaced
// because we may use this property after update has been installed
@property (nonatomic, readonly) NSString *oldHostName;
@property (nonatomic, readonly) NSURL *oldHostBundleURL;

@property (nonatomic, weak, nullable, readonly) id <SPUStandardUserDriverDelegate> delegate;

@property (nonatomic, copy) void (^installUpdateHandler)(SPUUserUpdateChoice);
@property (nonatomic, copy) void (^cancellation)(void);

@property (nonatomic) SUStatusController *checkingController;
@property (nonatomic) SUUpdateAlert *activeUpdateAlert;
@property (nonatomic) SUStatusController *statusController;
@property (nonatomic) SUUpdatePermissionPrompt *permissionPrompt;

@property (nonatomic) uint64_t expectedContentLength;
@property (nonatomic) uint64_t bytesDownloaded;

@property (nonatomic, readonly) uint64_t initializationTime;

@end

@implementation SPUStandardUserDriver
{
    NSValue *_updateAlertWindowFrameValue;
    BOOL _loggedGentleUpdateReminderWarning;
    BOOL _regularApplicationUpdate;
}

@synthesize host = _host;
@synthesize oldHostName = _oldHostName;
@synthesize oldHostBundleURL = _oldHostBundleURL;
@synthesize installUpdateHandler = _installUpdateHandler;
@synthesize cancellation = _cancellation;
@synthesize delegate = _delegate;
@synthesize checkingController = _checkingController;
@synthesize activeUpdateAlert = _activeUpdateAlert;
@synthesize statusController = _statusController;
@synthesize permissionPrompt = _permissionPrompt;
@synthesize expectedContentLength = _expectedContentLength;
@synthesize bytesDownloaded = _bytesDownloaded;
@synthesize initializationTime = _initializationTime;

#pragma mark Birth

- (instancetype)initWithHostBundle:(NSBundle *)hostBundle delegate:(nullable id<SPUStandardUserDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _host = [[SUHost alloc] initWithBundle:hostBundle];
        _oldHostName = _host.name;
        _oldHostBundleURL = hostBundle.bundleURL;
        _delegate = delegate;
        
        if (@available(macOS 10.12, *)) {
            _initializationTime = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
        }
    }
    return self;
}

#pragma mark Update Permission

- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply
{
    assert(NSThread.isMainThread);
    
    if ([SUApplicationInfo isBackgroundApplication:[NSApplication sharedApplication]]) {
        [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    }
    
    __weak __typeof__(self) weakSelf = self;
    self.permissionPrompt = [[SUUpdatePermissionPrompt alloc] initPromptWithHost:self.host request:request reply:^(SUUpdatePermissionResponse *response) {
        reply(response);
        weakSelf.permissionPrompt = nil;
    }];
    
    [self.permissionPrompt showWindow:nil];
}

#pragma mark Update Alert Focus

// This private method is used by SPUUpdater when scheduling for update checks
- (void)_logGentleScheduledUpdateReminderWarningIfNeeded
{
    id<SPUStandardUserDriverDelegate> delegate = self.delegate;
    if (!_loggedGentleUpdateReminderWarning && (![delegate respondsToSelector:@selector(supportsGentleScheduledUpdateReminders)] || !delegate.supportsGentleScheduledUpdateReminders)) {
        BOOL isBackgroundApp = [SUApplicationInfo isBackgroundApplication:[NSApplication sharedApplication]];
        if (isBackgroundApp) {
            SULog(SULogLevelError, @"Warning: Background app automatically schedules for update checks but does not implement gentle scheduled update reminders. Please visit ... and implement -[SPUStandardUserDriverDelegate supportsGentleScheduledUpdateReminders]. This warning will only be logged once.");
            
            _loggedGentleUpdateReminderWarning = YES;
        }
    }
}

// updateItem should be non-nil when showing update for first time for scheduled updates
- (void)setUpActiveUpdateAlertRequestingFocus:(BOOL)requestingFocus appcastItem:(SUAppcastItem * _Nullable)updateItem
{
    // Make sure the window is loaded in any case
    [self.activeUpdateAlert window];
    
    [self _removeScheduledUpdateAlertAfterDelay];
    
    // If the app is a menubar app or the like, we need to focus it first and alter the
    // update prompt to behave like a normal window. Otherwise if the window were hidden
    // there may be no way for the application to be activated to make it visible again.
    BOOL isBackgroundApp = [SUApplicationInfo isBackgroundApplication:[NSApplication sharedApplication]];
    if (isBackgroundApp) {
        BOOL handleShowingUpdates;
        if (updateItem != nil && [self.delegate respondsToSelector:@selector(standardUserDriverShouldShowAlertForScheduledUpdate:inFocusNow:)]) {
            handleShowingUpdates = [self.delegate standardUserDriverShouldShowAlertForScheduledUpdate:(SUAppcastItem * _Nonnull)updateItem inFocusNow:requestingFocus];
        } else {
            handleShowingUpdates = YES;
        }
        
        // For background applications we always have install button in focus
        [self.activeUpdateAlert setInstallButtonFocus:YES];
        
        // If we don't handle showing updates, the delegate will handle it later
        if (handleShowingUpdates) {
            if (requestingFocus) {
                [NSApp activateIgnoringOtherApps:YES];
            }
            
            [self.activeUpdateAlert showWindow:nil];
        }
    } else {
        // Only show the update alert if the app is active and if it's an an opportune time; otherwise, we'll wait until the app becomes active and the time is right
        BOOL driverShowingUpdateNow;
        BOOL registerScheduledUpdateCheckDelay;
        if ([NSApp isActive]) {
            // If the system has been inactive for several minutes, allow the update alert to show up immediately. We assume it's likely the user isn't at their computer in this case.
            CFTimeInterval timeSinceLastEvent;
            if (!requestingFocus) {
                timeSinceLastEvent = CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateHIDSystemState, kCGAnyInputEventType);
            } else {
                timeSinceLastEvent = 0;
            }
            
            if (requestingFocus || timeSinceLastEvent >= SUScheduledUpdateIdleEventLeewayInterval) {
                driverShowingUpdateNow = YES;
                registerScheduledUpdateCheckDelay = NO;
            } else {
                registerScheduledUpdateCheckDelay = YES;
                driverShowingUpdateNow = NO;
            }
        } else {
            // We will show the update alert when the user comes back to the app
            driverShowingUpdateNow = NO;
            registerScheduledUpdateCheckDelay = NO;
        }
        
        BOOL handleShowingUpdates;
        if (updateItem != nil && [self.delegate respondsToSelector:@selector(standardUserDriverShouldShowAlertForScheduledUpdate:inFocusNow:)]) {
            handleShowingUpdates = [self.delegate standardUserDriverShouldShowAlertForScheduledUpdate:(SUAppcastItem * _Nonnull)updateItem inFocusNow:driverShowingUpdateNow];
        } else {
            handleShowingUpdates = YES;
        }
        
        if (!handleShowingUpdates) {
            // Let the delegate handle showing the update alert later
            [self.activeUpdateAlert setInstallButtonFocus:YES];
        } else {
            if (!driverShowingUpdateNow) {
                if (registerScheduledUpdateCheckDelay) {
                    // If the application does not become inactive and active again within a threshold,
                    // we will give up and show the update
                    [self performSelector:@selector(showScheduledUpdateAlertAfterDelay) withObject:nil afterDelay:SUScheduledUpdateActiveAppLeewayInterval];
                }
                
                [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
            } else {
                [self.activeUpdateAlert showWindow:nil];
                [self.activeUpdateAlert setInstallButtonFocus:YES];
            }
        }
    }
}

- (void)_removeApplicationBecomeActiveObserver
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationDidBecomeActiveNotification object:NSApp];
}

- (void)_removeScheduledUpdateAlertAfterDelay
{
    [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(showScheduledUpdateAlertAfterDelay) object:nil];
}

- (void)showScheduledUpdateAlertAfterDelay
{
    [self.activeUpdateAlert showWindow:nil];
    [self.activeUpdateAlert setInstallButtonFocus:NO];
}

- (void)applicationDidBecomeActive:(NSNotification *)__unused aNotification
{
    [self _removeScheduledUpdateAlertAfterDelay];
    
    [self.activeUpdateAlert showWindow:nil];
    [self.activeUpdateAlert setInstallButtonFocus:YES];
    
    [self _removeApplicationBecomeActiveObserver];
}

#pragma mark Update Found

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply
{
    assert(NSThread.isMainThread);
    
    [self closeCheckingWindow];
    
    id <SUVersionDisplay> versionDisplayer = nil;
    if ([self.delegate respondsToSelector:@selector(standardUserDriverRequestsVersionDisplayer)]) {
        versionDisplayer = [self.delegate standardUserDriverRequestsVersionDisplayer];
    }
    
    __weak SPUStandardUserDriver *weakSelf = self;
    __weak id<SPUStandardUserDriverDelegate> weakDelegate = self.delegate;
    self.activeUpdateAlert = [[SUUpdateAlert alloc] initWithAppcastItem:appcastItem state:state host:self.host versionDisplayer:versionDisplayer completionBlock:^(SPUUserUpdateChoice choice) {
        reply(choice);
        
        id<SPUStandardUserDriverDelegate> strongDelegate = weakDelegate;
        if (strongDelegate != nil && [strongDelegate respondsToSelector:@selector(standardUserDriverWillCloseAlertForUpdate:)]) {
            [strongDelegate standardUserDriverWillCloseAlertForUpdate:appcastItem];
        }
        
        SPUStandardUserDriver *strongSelf = weakSelf;
        if (strongSelf != nil) {
            // Record the window frame of the update alert right before we deallocate it
            // So we can center future status window to where the update alert last was
            NSWindow *updateAlertWindow = strongSelf.activeUpdateAlert.window;
            if (updateAlertWindow != nil) {
                strongSelf->_updateAlertWindowFrameValue = [NSValue valueWithRect:updateAlertWindow.frame];
            }
            strongSelf.activeUpdateAlert = nil;
        }
    } didBecomeKeyBlock:^{
        id<SPUStandardUserDriverDelegate> strongDelegate = weakDelegate;
        if ([strongDelegate respondsToSelector:@selector(standardUserDriverDidMakeAlertWindowKeyForUpdate:)]) {
            [strongDelegate standardUserDriverDidMakeAlertWindowKeyForUpdate:appcastItem];
        }
    }];
    
    _regularApplicationUpdate = [appcastItem.installationType isEqualToString:SPUInstallationTypeApplication];
    
    BOOL allowInstallButtonFocus;
    if (state.userInitiated) {
        allowInstallButtonFocus = YES;
    } else {
        if (@available(macOS 10.12, *)) {
            uint64_t currentTime = clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
            uint64_t timeElapsedSinceInitialization = currentTime - self.initializationTime;
            
            // Allow the install button to focus if 3 or less seconds have passed since initialization
            allowInstallButtonFocus = (timeElapsedSinceInitialization <= 3000000000ULL);
        } else {
            allowInstallButtonFocus = NO;
        }
    }
    [self setUpActiveUpdateAlertRequestingFocus:allowInstallButtonFocus appcastItem:(state.userInitiated ? nil : appcastItem)];
}

- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData
{
    assert(NSThread.isMainThread);
    
    [self.activeUpdateAlert showUpdateReleaseNotesWithDownloadData:downloadData];
}

- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error
{
    assert(NSThread.isMainThread);
    
    // I don't want to expose SULog here because it's more of a user driver facing error
    // For our purposes we just ignore it and continue on..
    NSLog(@"Failed to download release notes with error: %@", error);
    [self.activeUpdateAlert showReleaseNotesFailedToDownload];
}

- (void)showUpdateInFocus
{
    if (self.activeUpdateAlert != nil) {
        [self setUpActiveUpdateAlertRequestingFocus:YES appcastItem:nil];
    } else if (self.permissionPrompt != nil) {
        [self.permissionPrompt showWindow:nil];
    } else if (self.statusController != nil) {
        [self.statusController showWindow:nil];
    }
}

#pragma mark Install & Relaunch Update

- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))installUpdateHandler
{
    assert(NSThread.isMainThread);
    
    [self createAndShowStatusController];
    
    [self.statusController beginActionWithTitle:SULocalizedString(@"Ready to Install", nil) maxProgressValue:1.0 statusText:nil];
    [self.statusController setProgressValue:1.0]; // Fill the bar.
    [self.statusController setButtonEnabled:YES];
    [self.statusController setButtonTitle:SULocalizedString(@"Install and Relaunch", nil) target:self action:@selector(installAndRestart:) isDefault:YES];
    
    [NSApp requestUserAttention:NSInformationalRequest];
    
    self.installUpdateHandler = installUpdateHandler;
}

- (void)installAndRestart:(id)__unused sender
{
    if (self.installUpdateHandler != nil) {
        self.installUpdateHandler(SPUUserUpdateChoiceInstall);
        self.installUpdateHandler = nil;
    }
}

#pragma mark Check for Updates

- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation
{
    assert(NSThread.isMainThread);
    
    self.cancellation = cancellation;
    
    self.checkingController = [[SUStatusController alloc] initWithHost:self.host centerPointValue:nil minimizable:NO];
    [[self.checkingController window] center]; // Force the checking controller to load its window.
    [self.checkingController beginActionWithTitle:SULocalizedString(@"Checking for updates…", nil) maxProgressValue:0.0 statusText:nil];
    [self.checkingController setButtonTitle:SULocalizedString(@"Cancel", nil) target:self action:@selector(cancelCheckForUpdates:) isDefault:NO];
    [self.checkingController showWindow:self];
    
    // For background applications, obtain focus.
    // Useful if the update check is requested from another app like System Preferences.
    if ([SUApplicationInfo isBackgroundApplication:[NSApplication sharedApplication]])
    {
        [NSApp activateIgnoringOtherApps:YES];
    }
}

- (void)closeCheckingWindow
{
    if (self.checkingController != nil)
    {
        [self.checkingController close];
        self.checkingController = nil;
        self.cancellation = nil;
    }
}

- (void)cancelCheckForUpdates:(id)__unused sender
{
    if (self.cancellation != nil) {
        self.cancellation();
        self.cancellation = nil;
    }
    [self closeCheckingWindow];
}

#pragma mark Update Errors

- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement
{
    assert(NSThread.isMainThread);
    
    [self closeCheckingWindow];
    
    [self.statusController close];
    self.statusController = nil;
    
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = SULocalizedString(@"Update Error!", nil);
    alert.informativeText = [NSString stringWithFormat:@"%@", [error localizedDescription]];
    [alert addButtonWithTitle:SULocalizedString(@"Cancel Update", nil)];
    [self showAlert:alert secondaryAction:nil];
    
    acknowledgement();
}

- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement
{
    assert(NSThread.isMainThread);
    
    [self closeCheckingWindow];
    
    NSAlert *alert = [NSAlert alertWithError:error];
    alert.alertStyle = NSAlertStyleInformational;
    
    // Can we give more information to the user?
    SPUNoUpdateFoundReason reason = (SPUNoUpdateFoundReason)[(NSNumber *)error.userInfo[SPUNoUpdateFoundReasonKey] integerValue];
    
    void (^secondaryAction)(void) = nil;
    SUAppcastItem *latestAppcastItem = error.userInfo[SPULatestAppcastItemFoundKey];
    if (latestAppcastItem != nil) {
        switch (reason) {
            case SPUNoUpdateFoundReasonOnLatestVersion:
            case SPUNoUpdateFoundReasonOnNewerThanLatestVersion: {
                // Show the user the past version history if available
                NSString *localizedButtonTitle = SULocalizedString(@"Version History", nil);

                // Check if the delegate implements a Version History action
                id <SPUStandardUserDriverDelegate> delegate = self.delegate;
                
                if ([delegate respondsToSelector:@selector(standardUserDriverShowVersionHistoryForAppcastItem:)]) {
                    [alert addButtonWithTitle:localizedButtonTitle];
                    
                    secondaryAction = ^{
                        [delegate standardUserDriverShowVersionHistoryForAppcastItem:latestAppcastItem];
                    };
                } else if (latestAppcastItem.fullReleaseNotesURL != nil) {
                    // Open the full release notes URL if informed
                    [alert addButtonWithTitle:localizedButtonTitle];
                    
                    secondaryAction = ^{
                        [[NSWorkspace sharedWorkspace] openURL:(NSURL * _Nonnull)latestAppcastItem.fullReleaseNotesURL];
                    };
                } else if (latestAppcastItem.releaseNotesURL != nil) {
                    // Fall back to opening the release notes URL
                    [alert addButtonWithTitle:localizedButtonTitle];
                    
                    secondaryAction = ^{
                        [[NSWorkspace sharedWorkspace] openURL:(NSURL * _Nonnull)latestAppcastItem.releaseNotesURL];
                    };
                }
                
                break;
            }
            case SPUNoUpdateFoundReasonSystemIsTooOld:
            case SPUNoUpdateFoundReasonSystemIsTooNew:
                if (latestAppcastItem.infoURL != nil) {
                    // Show the user the product's link if available
                    [alert addButtonWithTitle:SULocalizedString(@"Learn More…", nil)];
                    
                    secondaryAction = ^{
                        [[NSWorkspace sharedWorkspace] openURL:(NSURL * _Nonnull)latestAppcastItem.infoURL];
                    };
                }
                break;
            case SPUNoUpdateFoundReasonUnknown:
                break;
        }
    }
    
    [self showAlert:alert secondaryAction:secondaryAction];
    
    acknowledgement();
}

- (void)showAlert:(NSAlert *)alert secondaryAction:(void (^ _Nullable)(void))secondaryAction
{
    id <SPUStandardUserDriverDelegate> delegate = self.delegate;
    
    if ([delegate respondsToSelector:@selector(standardUserDriverWillShowModalAlert)]) {
        [delegate standardUserDriverWillShowModalAlert];
    }
    
    [alert setIcon:[SUApplicationInfo bestIconForHost:self.host]];
    
    NSModalResponse response = [alert runModal];
    if (response == NSAlertSecondButtonReturn && secondaryAction != nil) {
        secondaryAction();
    }
    
    if ([delegate respondsToSelector:@selector(standardUserDriverDidShowModalAlert)]) {
        [delegate standardUserDriverDidShowModalAlert];
    }
}

#pragma mark Download & Install Updates

- (void)createAndShowStatusController
{
    if (self.statusController == nil) {
        // We will make the status window minimizable for regular app updates which are often
        // quick and atomic to install on quit. But we won't do this for package based updates.
        BOOL minimizable;
        if (!_regularApplicationUpdate) {
            minimizable = NO;
        } else if ([self.delegate respondsToSelector:@selector(standardUserDriverAllowsMinimizableStatusWindow)]) {
            minimizable = [self.delegate standardUserDriverAllowsMinimizableStatusWindow];
        } else {
            minimizable = YES;
        }
        
        NSValue *centerPointValue;
        if (_updateAlertWindowFrameValue != nil) {
            NSRect updateAlertFrame = _updateAlertWindowFrameValue.rectValue;
            NSPoint centerPoint = NSMakePoint(updateAlertFrame.origin.x + updateAlertFrame.size.width / 2.0, updateAlertFrame.origin.y + updateAlertFrame.size.height / 2.0);
            
            centerPointValue = [NSValue valueWithPoint:centerPoint];
        } else {
            centerPointValue = nil;
        }
        
        self.statusController = [[SUStatusController alloc] initWithHost:self.host centerPointValue:centerPointValue minimizable:minimizable];
        [self.statusController showWindow:self];
    }
}

- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation
{
    assert(NSThread.isMainThread);
    
    self.cancellation = cancellation;
    
    [self createAndShowStatusController];
    
    [self.statusController beginActionWithTitle:SULocalizedString(@"Downloading update…", @"Take care not to overflow the status window.") maxProgressValue:1.0 statusText:nil];
    [self.statusController setProgressValue:0.0];
    [self.statusController setButtonTitle:SULocalizedString(@"Cancel", nil) target:self action:@selector(cancelDownload:) isDefault:NO];
    
    self.bytesDownloaded = 0;
}

- (void)cancelDownload:(id)__unused sender
{
    if (self.cancellation != nil) {
        self.cancellation();
        self.cancellation = nil;
    }
}

- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)expectedContentLength
{
    assert(NSThread.isMainThread);
    
    self.expectedContentLength = expectedContentLength;
    if (expectedContentLength == 0) {
        [self.statusController setMaxProgressValue:0.0];
    }
}

- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length
{
    assert(NSThread.isMainThread);

    self.bytesDownloaded += length;

    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    [formatter setZeroPadsFractionDigits:YES];

    if (self.expectedContentLength > 0.0) {
        double newProgressValue = (double)self.bytesDownloaded / (double)self.expectedContentLength;
        
        [self.statusController setProgressValue:MIN(newProgressValue, 1.0)];
        
        [self.statusController setStatusText:[NSString stringWithFormat:SULocalizedString(@"%@ of %@", @"The download progress in units of bytes, e.g. 100 KB of 1,0 MB"), [formatter stringFromByteCount:(long long)self.bytesDownloaded], [formatter stringFromByteCount:(long long)MAX(self.bytesDownloaded, self.expectedContentLength)]]];
    } else {
        [self.statusController setStatusText:[NSString stringWithFormat:SULocalizedString(@"%@ downloaded", @"The download progress in a unit of bytes, e.g. 100 KB"), [formatter stringFromByteCount:(long long)self.bytesDownloaded]]];
    }
}

- (void)showDownloadDidStartExtractingUpdate
{
    assert(NSThread.isMainThread);
    
    self.cancellation = nil;
    
    [self createAndShowStatusController];
    [self.statusController beginActionWithTitle:SULocalizedString(@"Extracting update…", @"Take care not to overflow the status window.") maxProgressValue:1.0 statusText:nil];
    [self.statusController setProgressValue:0.0];
    [self.statusController setButtonTitle:SULocalizedString(@"Cancel", nil) target:nil action:nil isDefault:NO];
    [self.statusController setButtonEnabled:NO];
}

- (void)showExtractionReceivedProgress:(double)progress
{
    assert(NSThread.isMainThread);
    
    [self.statusController setProgressValue:progress];
}

- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)applicationTerminated
{
    assert(NSThread.isMainThread);
    
    if (applicationTerminated) {
        [self.statusController beginActionWithTitle:SULocalizedString(@"Installing update…", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
        [self.statusController setButtonEnabled:NO];
    } else {
        // The "quit" event can always be canceled or delayed by the application we're updating
        // So we can't easily predict how long the installation will take or if it won't happen right away
        // We close our status window because we don't want it persisting for too long and have it obscure other windows
        [self.statusController close];
        self.statusController = nil;
    }
}

- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))acknowledgement
{
    assert(NSThread.isMainThread);
    
    // Close window showing update is installing
    [self.statusController close];
    self.statusController = nil;
    
    // Only show installed prompt when the app is not relaunched
    // When the app is relaunched, there is enough of a UI from relaunching the app.
    if (!relaunched) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = SULocalizedString(@"Update Installed", nil);
        
        // Extract information from newly updated bundle if available
        NSString *hostName;
        NSString *hostVersion;
        NSBundle *newBundle = [NSBundle bundleWithURL:self.oldHostBundleURL];
        if (newBundle != nil) {
            SUHost *newHost = [[SUHost alloc] initWithBundle:newBundle];
            hostName = newHost.name;
            hostVersion = newHost.displayVersion;
        } else {
            // This may happen if Sparkle's normalization is enabled
            hostName = self.oldHostName;
            hostVersion = nil;
        }
        
        if (hostVersion != nil) {
            alert.informativeText = [NSString stringWithFormat:SULocalizedString(@"%@ is now updated to version %@!", nil), hostName, hostVersion];
        } else {
            alert.informativeText = [NSString stringWithFormat:SULocalizedString(@"%@ is now updated!", nil), hostName];
        }
        [self showAlert:alert secondaryAction:nil];
    }
    
    acknowledgement();
}

#pragma mark Aborting Everything

- (void)dismissUpdateInstallation
{
    assert(NSThread.isMainThread);
    
    self.installUpdateHandler = nil;
    self.cancellation = nil;
    
    [self closeCheckingWindow];
    
    if (self.permissionPrompt) {
        [self.permissionPrompt close];
        self.permissionPrompt = nil;
    }
    
    if (self.statusController) {
        [self.statusController close];
        self.statusController = nil;
    }
    
    if (self.activeUpdateAlert) {
        [self.activeUpdateAlert close];
        self.activeUpdateAlert = nil;
    }
    
    [self _removeApplicationBecomeActiveObserver];
    [self _removeScheduledUpdateAlertAfterDelay];
}

@end

#endif
