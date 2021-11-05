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

#import <AppKit/AppKit.h>

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

@end

@implementation SPUStandardUserDriver

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

#pragma mark Birth

- (instancetype)initWithHostBundle:(NSBundle *)hostBundle delegate:(nullable id<SPUStandardUserDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _host = [[SUHost alloc] initWithBundle:hostBundle];
        _oldHostName = _host.name;
        _oldHostBundleURL = hostBundle.bundleURL;
        _delegate = delegate;
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

- (void)setUpFocusForActiveUpdateAlertWithUserInitiation:(BOOL)userInitiated
{
    // Make sure the window is loaded in any case
    [self.activeUpdateAlert window];
    
    // If the app is a menubar app or the like, we need to focus it first and alter the
    // update prompt to behave like a normal window. Otherwise if the window were hidden
    // there may be no way for the application to be activated to make it visible again.
    if ([SUApplicationInfo isBackgroundApplication:[NSApplication sharedApplication]]) {
        [NSApp activateIgnoringOtherApps:YES];
    }
    
    // Only show the update alert if the app is active; otherwise, we'll wait until it is.
    if ([NSApp isActive]) {
        [self.activeUpdateAlert setInstallButtonFocus:userInitiated];
        [self.activeUpdateAlert showWindow:nil];
    } else {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
    }
}

- (void)applicationDidBecomeActive:(NSNotification *)__unused aNotification
{
    [self.activeUpdateAlert showWindow:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationDidBecomeActiveNotification object:NSApp];
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
    self.activeUpdateAlert = [[SUUpdateAlert alloc] initWithAppcastItem:appcastItem state:state host:self.host versionDisplayer:versionDisplayer completionBlock:^(SPUUserUpdateChoice choice) {
        reply(choice);
        weakSelf.activeUpdateAlert = nil;
    }];
    
    [self setUpFocusForActiveUpdateAlertWithUserInitiation:state.userInitiated];
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
        [self setUpFocusForActiveUpdateAlertWithUserInitiation:YES];
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
    
    self.checkingController = [[SUStatusController alloc] initWithHost:self.host];
    [[self.checkingController window] center]; // Force the checking controller to load its window.
    [self.checkingController beginActionWithTitle:SULocalizedString(@"Checking for updates...", nil) maxProgressValue:0.0 statusText:nil];
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
                    [alert addButtonWithTitle:SULocalizedString(@"Learn More...", nil)];
                    
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
    
    // When showing a modal alert we need to ensure that background applications
    // are focused to inform the user since there is no dock icon to notify them.
    if ([SUApplicationInfo isBackgroundApplication:[NSApplication sharedApplication]]) { [[NSApplication sharedApplication] activateIgnoringOtherApps:YES]; }
    
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
        self.statusController = [[SUStatusController alloc] initWithHost:self.host];
        [self.statusController showWindow:self];
    }
}

- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation
{
    assert(NSThread.isMainThread);
    
    self.cancellation = cancellation;
    
    [self createAndShowStatusController];
    [self.statusController beginActionWithTitle:SULocalizedString(@"Downloading update...", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
    [self.statusController setButtonTitle:SULocalizedString(@"Cancel", nil) target:self action:@selector(cancelDownload:) isDefault:NO];
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
    
    [self.statusController setMaxProgressValue:expectedContentLength];
}

- (NSString *)localizedStringFromByteCount:(long long)value
{
    if (![SUOperatingSystem isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){10, 8, 0}]) {
        if (value < 1000) {
            return [NSString stringWithFormat:@"%.0lf %@", value / 1.0,
                    SULocalizedString(@"B", @"the unit for bytes")];
        }
        
        if (value < 1000 * 1000) {
            return [NSString stringWithFormat:@"%.0lf %@", value / 1000.0,
                    SULocalizedString(@"KB", @"the unit for kilobytes")];
        }
        
        if (value < 1000 * 1000 * 1000) {
            return [NSString stringWithFormat:@"%.1lf %@", value / 1000.0 / 1000.0,
                    SULocalizedString(@"MB", @"the unit for megabytes")];
        }
        
        return [NSString stringWithFormat:@"%.2lf %@", value / 1000.0 / 1000.0 / 1000.0,
                SULocalizedString(@"GB", @"the unit for gigabytes")];
    }
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    [formatter setZeroPadsFractionDigits:YES];
    return [formatter stringFromByteCount:value];
#pragma clang diagnostic pop
}

- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length
{
    assert(NSThread.isMainThread);
    
    double newProgressValue = [self.statusController progressValue] + (double)length;
    
    // In case our expected content length was incorrect
    if (newProgressValue > [self.statusController maxProgressValue]) {
        [self.statusController setMaxProgressValue:newProgressValue];
    }
    
    [self.statusController setProgressValue:newProgressValue];
    if ([self.statusController maxProgressValue] > 0.0)
        [self.statusController setStatusText:[NSString stringWithFormat:SULocalizedString(@"%@ of %@", nil), [self localizedStringFromByteCount:(long long)self.statusController.progressValue], [self localizedStringFromByteCount:(long long)self.statusController.maxProgressValue]]];
    else
        [self.statusController setStatusText:[NSString stringWithFormat:SULocalizedString(@"%@ downloaded", nil), [self localizedStringFromByteCount:(long long)self.statusController.progressValue]]];
}

- (void)showDownloadDidStartExtractingUpdate
{
    assert(NSThread.isMainThread);
    
    self.cancellation = nil;
    
    [self createAndShowStatusController];
    [self.statusController beginActionWithTitle:SULocalizedString(@"Extracting update...", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
    [self.statusController setButtonTitle:SULocalizedString(@"Cancel", nil) target:nil action:nil isDefault:NO];
    [self.statusController setButtonEnabled:NO];
}

- (void)showExtractionReceivedProgress:(double)progress
{
    assert(NSThread.isMainThread);
    
    if ([self.statusController maxProgressValue] == 0.0) {
        [self.statusController setMaxProgressValue:1];
    }
    [self.statusController setProgressValue:progress];
}

- (void)showInstallingUpdate
{
    assert(NSThread.isMainThread);
    
    [self.statusController beginActionWithTitle:SULocalizedString(@"Installing update...", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
    [self.statusController setButtonEnabled:NO];
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
            alert.informativeText = [NSString stringWithFormat:SULocalizedString(@"%@ is now updated to version %@!", nil), hostName, hostVersion];
        } else {
            alert.informativeText = [NSString stringWithFormat:SULocalizedString(@"%@ is now updated!", nil), hostName];
        }
        [self showAlert:alert secondaryAction:nil];
    }
    
    acknowledgement();
}

#pragma mark Aborting Everything

- (void)showSendingTerminationSignal
{
    assert(NSThread.isMainThread);
    
    // The "quit" event can always be canceled or delayed by the application we're updating
    // So we can't easily predict how long the installation will take or if it won't happen right away
    // We close our status window because we don't want it persisting for too long and have it obscure other windows
    [self.statusController close];
    self.statusController = nil;
}

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
}

@end

#endif
