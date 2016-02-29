//
//  SUSparkleUserUpdaterDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/14/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUSparkleUserUpdaterDriver.h"
#import "SUAppcastItem.h"
#import "SUVersionDisplayProtocol.h"
#import "SUHost.h"
#import "SUUpdatePermissionPrompt.h"
#import "SUStatusController.h"
#import "SUUpdateAlert.h"
#import "SUAutomaticUpdateAlert.h"
#import "SUOperatingSystem.h"
#import "SULocalizations.h"
#import "SUApplicationInfo.h"

#if __MAC_OS_X_VERSION_MAX_ALLOWED < 1080
@interface NSByteCountFormatter : NSFormatter {
@private
    unsigned int _allowedUnits;
    char _countStyle;
    BOOL _allowsNonnumericFormatting, _includesUnit, _includesCount, _includesActualByteCount,
    _adaptive, _zeroPadsFractionDigits;
    int _formattingContext;
    int _reserved[5];
}
+ (NSString *)stringFromByteCount:(long long)byteCount
                       countStyle:(NSByteCountFormatterCountStyle)countStyle;
@end
#endif

@interface SUSparkleUserUpdaterDriver ()

@property (nonatomic, readonly) SUHost *host;

@property (nonatomic) BOOL askedHandlingTermination;
@property (nonatomic, readonly) BOOL handlesTermination;

@property (nonatomic) BOOL updateInProgress;

@property (nonatomic) NSTimer *checkUpdateTimer;
@property (nonatomic, copy) void (^checkForUpdatesReply)(SUUpdateCheckTimerStatus);

@property (nonatomic) SUStatusController *checkingController;
@property (nonatomic, copy) void (^updateCheckStatusCompletion)(SUUserInitiatedCheckStatus);

@property (nonatomic) NSWindowController *activeUpdateAlert;

@property (nonatomic) SUStatusController *statusController;
@property (nonatomic, copy) void (^downloadStatusCompletion)(SUDownloadUpdateStatus);
@property (nonatomic, copy) void (^installUpdateHandler)(SUInstallUpdateStatus);

@property (nonatomic, copy) void (^applicationTerminationHandler)(SUApplicationTerminationStatus);

@property (nonatomic, copy) void (^systemPowerOffHandler)(SUSystemPowerOffStatus);

@property (nonatomic) BOOL installingUpdateOnTermination;

@end

@implementation SUSparkleUserUpdaterDriver

@synthesize host = _host;
@synthesize handlesTermination = _handlesTermination;
@synthesize askedHandlingTermination = _askedHandlingTermination;
@synthesize delegate = _delegate;
@synthesize updateInProgress = _updateInProgress;
@synthesize checkUpdateTimer = _checkUpdateTimer;
@synthesize checkForUpdatesReply = _checkForUpdatesReply;
@synthesize checkingController = _checkingController;
@synthesize updateCheckStatusCompletion = _updateCheckStatusCompletion;
@synthesize activeUpdateAlert = _activeUpdateAlert;
@synthesize statusController = _statusController;
@synthesize downloadStatusCompletion = _downloadStatusCompletion;
@synthesize installUpdateHandler = _installUpdateHandler;
@synthesize applicationTerminationHandler = _applicationTerminationHandler;
@synthesize systemPowerOffHandler = _systemPowerOffHandler;
@synthesize installingUpdateOnTermination = _installingUpdateOnTermination;

#pragma mark Birth

- (instancetype)initWithHostBundle:(NSBundle *)hostBundle delegate:(id<SUUserUpdaterDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _host = [[SUHost alloc] initWithBundle:hostBundle];
        _delegate = delegate;
    }
    return self;
}

#pragma mark Is Update Busy?

- (void)showUpdateInProgress:(BOOL)isUpdateInProgress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.updateInProgress = isUpdateInProgress;
    });
}

- (BOOL)handlesTermination
{
    if (!self.askedHandlingTermination) {
        if ([self.delegate respondsToSelector:@selector(responsibleForSignalingApplicationTerminationForUserDriver:)]) {
            _handlesTermination = ![self.delegate responsibleForSignalingApplicationTerminationForUserDriver:self];
        } else {
            _handlesTermination = YES;
        }
        self.askedHandlingTermination = YES;
    }
    return _handlesTermination;
}

#pragma mark Check Updates Timer

- (BOOL)isDelegateResponsibleForUpdateChecking
{
    BOOL result = NO;
    if ([self.delegate respondsToSelector:@selector(responsibleForInitiatingUpdateCheckForUserDriver:)]) {
        result = [self.delegate responsibleForInitiatingUpdateCheckForUserDriver:self];
    }
    return result;
}

- (void)checkForUpdates:(NSTimer *)__unused timer
{
    if ([self isDelegateResponsibleForUpdateChecking]) {
        if ([self.delegate respondsToSelector:@selector(initiateUpdateCheckForUserDriver:)]) {
            [self.delegate initiateUpdateCheckForUserDriver:self];
        } else {
            NSLog(@"Error: Delegate %@ for user driver %@ must implement initiateUpdateCheckForUserDriver: because it returned YES from responsibleForInitiatingUpdateCheckForUserDriver:", self.delegate, self);
        }
    } else {
        if (self.checkForUpdatesReply != nil) {
            self.checkForUpdatesReply(SUCheckForUpdateNow);
            self.checkForUpdatesReply = nil;
        }
    }
}

- (void)startUpdateCheckTimerWithNextTimeInterval:(NSTimeInterval)timeInterval reply:(void (^)(SUUpdateCheckTimerStatus))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self isDelegateResponsibleForUpdateChecking]) {
            reply(SUCheckForUpdateWillOccurLater);
        } else {
            self.checkForUpdatesReply = reply;
        }
        
        self.checkUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:timeInterval target:self selector:@selector(checkForUpdates:) userInfo:nil repeats:NO];
    });
}

- (void)_invalidateUpdateCheckTimer
{
    if (self.checkUpdateTimer != nil) {
        [self.checkUpdateTimer invalidate];
        self.checkUpdateTimer = nil;
        
        if (self.checkForUpdatesReply != nil) {
            self.checkForUpdatesReply(SUCheckForUpdateWillOccurLater);
            self.checkForUpdatesReply = nil;
        }
    }
}

- (void)invalidateUpdateCheckTimer
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _invalidateUpdateCheckTimer];
    });
}

#pragma mark Update Permission

- (void)requestUpdatePermissionWithSystemProfile:(NSArray *)systemProfile reply:(void (^)(SUUpdatePermissionPromptResult *))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // This shows a modal alert dialog which unlike other alerts cannot be closed until the user makes a decision
        // This means that we can never programatically close the dialog if something goes horribly wrong
        // But this dialog should only show up once in the application's lifetime so this may be an OK decision
        [SUUpdatePermissionPrompt promptWithHost:self.host systemProfile:systemProfile reply:reply];
    });
}

#pragma mark Update Alert Focus

- (void)setUpFocusForActiveUpdateAlert
{
    // If the app is a menubar app or the like, we need to focus it first and alter the
    // update prompt to behave like a normal window. Otherwise if the window were hidden
    // there may be no way for the application to be activated to make it visible again.
    if ([SUApplicationInfo isBackgroundApplication:NSApp]) {
        [self.activeUpdateAlert.window setHidesOnDeactivate:NO];
        
        [NSApp activateIgnoringOtherApps:YES];
    }
    
    // Only show the update alert if the app is active; otherwise, we'll wait until it is.
    if ([NSApp isActive])
        [self.activeUpdateAlert.window makeKeyAndOrderFront:self];
    else
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
}

- (void)applicationDidBecomeActive:(NSNotification *)__unused aNotification
{
    [self.activeUpdateAlert.window makeKeyAndOrderFront:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationDidBecomeActiveNotification object:NSApp];
}

#pragma mark Update Found

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem versionDisplayer:(id<SUVersionDisplay>)versionDisplayer reply:(void (^)(SUUpdateAlertChoice))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        __weak SUSparkleUserUpdaterDriver *weakSelf = self;
        SUUpdateAlert *updateAlert = [[SUUpdateAlert alloc] initWithAppcastItem:appcastItem host:self.host completionBlock:^(SUUpdateAlertChoice choice) {
            reply(choice);
            weakSelf.activeUpdateAlert = nil;
        }];
        
        [updateAlert setVersionDisplayer:versionDisplayer];
        self.activeUpdateAlert = updateAlert;
        
        [self setUpFocusForActiveUpdateAlert];
    });
}

- (void)showAutomaticUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem reply:(void (^)(SUAutomaticInstallationChoice))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        __weak SUSparkleUserUpdaterDriver *weakSelf = self;
        self.activeUpdateAlert = [[SUAutomaticUpdateAlert alloc] initWithAppcastItem:appcastItem host:self.host completionBlock:^(SUAutomaticInstallationChoice choice) {
            reply(choice);
            weakSelf.activeUpdateAlert = nil;
        }];
        
        [self setUpFocusForActiveUpdateAlert];
    });
}

#pragma mark Install & Relaunch Update

- (void)showExtractionFinishedAndReadyToInstallAndRelaunch:(void (^)(SUInstallUpdateStatus))installUpdateHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.statusController beginActionWithTitle:SULocalizedString(@"Ready to Install", nil) maxProgressValue:1.0 statusText:nil];
        [self.statusController setProgressValue:1.0]; // Fill the bar.
        [self.statusController setButtonEnabled:YES];
        [self.statusController setButtonTitle:SULocalizedString(@"Install and Relaunch", nil) target:self action:@selector(installAndRestart:) isDefault:YES];
        [[self.statusController window] makeKeyAndOrderFront:self];
        [NSApp requestUserAttention:NSInformationalRequest];
        
        self.installUpdateHandler = installUpdateHandler;
    });
}

- (void)installAndRestart:(id)__unused sender
{
    if (self.installUpdateHandler != nil) {
        self.installUpdateHandler(SUInstallAndRelaunchUpdateNow);
        self.installUpdateHandler = nil;
    }
}

- (void)cancelInstallAndRestart
{
    if (self.installUpdateHandler != nil) {
        self.installUpdateHandler(SUCancelUpdateInstallation);
        self.installUpdateHandler = nil;
    }
}

#pragma mark Check for Updates

- (void)showUserInitiatedUpdateCheckWithCompletion:(void (^)(SUUserInitiatedCheckStatus))updateCheckStatusCompletion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.updateCheckStatusCompletion = updateCheckStatusCompletion;
        
        self.checkingController = [[SUStatusController alloc] initWithHost:self.host];
        [[self.checkingController window] center]; // Force the checking controller to load its window.
        [self.checkingController beginActionWithTitle:SULocalizedString(@"Checking for updates...", nil) maxProgressValue:0.0 statusText:nil];
        [self.checkingController setButtonTitle:SULocalizedString(@"Cancel", nil) target:self action:@selector(cancelCheckForUpdates:) isDefault:NO];
        [self.checkingController showWindow:self];
        
        // For background applications, obtain focus.
        // Useful if the update check is requested from another app like System Preferences.
        if ([SUApplicationInfo isBackgroundApplication:NSApp])
        {
            [NSApp activateIgnoringOtherApps:YES];
        }
    });
}

- (void)cancelCheckForUpdates
{
    if (self.updateCheckStatusCompletion != nil) {
        self.updateCheckStatusCompletion(SUUserInitiatedCheckCancelled);
        self.updateCheckStatusCompletion = nil;
    }
    
    if (self.checkingController != nil)
    {
        [[self.checkingController window] close];
        self.checkingController = nil;
    }
}

- (void)cancelCheckForUpdates:(id)__unused sender
{
    [self cancelCheckForUpdates];
}

- (void)dismissUserInitiatedUpdateCheck
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.updateCheckStatusCompletion != nil) {
            self.updateCheckStatusCompletion(SUUserInitiatedCheckDone);
            self.updateCheckStatusCompletion = nil;
        }
        
        if (self.checkingController != nil)
        {
            [[self.checkingController window] close];
            self.checkingController = nil;
        }
    });
}

#pragma mark Update Errors

- (void)showUpdaterError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = SULocalizedString(@"Update Error!", nil);
        alert.informativeText = [NSString stringWithFormat:@"%@", [error localizedDescription]];
        [alert addButtonWithTitle:SULocalizedString(@"Cancel Update", nil)];
        [self showAlert:alert];
    });
}

- (void)showUpdateNotFound
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = SULocalizedString(@"You're up-to-date!", "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
        alert.informativeText = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.", nil), [self.host name], [self.host displayVersion]];
        [alert addButtonWithTitle:SULocalizedString(@"OK", nil)];
        [self showAlert:alert];
    });
}

- (void)showAlert:(NSAlert *)alert
{
    dispatch_async(dispatch_get_main_queue(), ^{
        id <SUUserUpdaterDriverDelegate> delegate = self.delegate;
        
        if ([delegate respondsToSelector:@selector(userUpdaterDriverWillShowModalAlert:)]) {
            [delegate userUpdaterDriverWillShowModalAlert:self];
        }
        
        // When showing a modal alert we need to ensure that background applications
        // are focused to inform the user since there is no dock icon to notify them.
        if ([SUApplicationInfo isBackgroundApplication:NSApp]) { [NSApp activateIgnoringOtherApps:YES]; }
        
        [alert setIcon:[SUApplicationInfo bestIconForBundle:self.host.bundle]];
        [alert runModal];
        
        if ([delegate respondsToSelector:@selector(userUpdaterDriverDidShowModalAlert:)]) {
            [delegate userUpdaterDriverDidShowModalAlert:self];
        }
    });
}

#pragma mark Download & Install Updates

- (void)showDownloadInitiatedWithCompletion:(void (^)(SUDownloadUpdateStatus))downloadUpdateStatusCompletion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.downloadStatusCompletion = downloadUpdateStatusCompletion;
        
        self.statusController = [[SUStatusController alloc] initWithHost:self.host];
        [self.statusController beginActionWithTitle:SULocalizedString(@"Downloading update...", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
        [self.statusController setButtonTitle:SULocalizedString(@"Cancel", nil) target:self action:@selector(cancelDownload:) isDefault:NO];
        [self.statusController showWindow:self];
    });
}

- (void)cancelDownload
{
    if (self.downloadStatusCompletion != nil) {
        self.downloadStatusCompletion(SUDownloadUpdateCancelled);
        self.downloadStatusCompletion = nil;
    }
}

- (void)cancelDownload:(id)__unused sender
{
    [self cancelDownload];
}

- (void)showDownloadDidReceiveResponse:(NSURLResponse *)response
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.statusController setMaxProgressValue:[response expectedContentLength]];
    });
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
    
    return [NSByteCountFormatter stringFromByteCount:value
                                          countStyle:NSByteCountFormatterCountStyleFile];
}

- (void)showDownloadDidReceiveDataOfLength:(NSUInteger)length
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.statusController setProgressValue:[self.statusController progressValue] + (double)length];
        if ([self.statusController maxProgressValue] > 0.0)
            [self.statusController setStatusText:[NSString stringWithFormat:SULocalizedString(@"%@ of %@", nil), [self localizedStringFromByteCount:(long long)self.statusController.progressValue], [self localizedStringFromByteCount:(long long)self.statusController.maxProgressValue]]];
        else
            [self.statusController setStatusText:[NSString stringWithFormat:SULocalizedString(@"%@ downloaded", nil), [self localizedStringFromByteCount:(long long)self.statusController.progressValue]]];
    });
}

- (void)showDownloadFinishedAndStartedExtractingUpdate
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.downloadStatusCompletion != nil) {
            self.downloadStatusCompletion(SUDownloadUpdateDone);
            self.downloadStatusCompletion = nil;
        }
        
        [self.statusController beginActionWithTitle:SULocalizedString(@"Extracting update...", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
        [self.statusController setButtonEnabled:NO];
    });
}

- (void)showExtractionReceivedProgress:(double)progress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // We do this here instead of in extractUpdate so that we only have a determinate progress bar for archives with progress.
        if ([self.statusController maxProgressValue] == 0.0) {
            [self.statusController setMaxProgressValue:1];
        }
        [self.statusController setProgressValue:progress];
    });
}

- (void)showInstallingUpdate
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.statusController beginActionWithTitle:SULocalizedString(@"Installing update...", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
        [self.statusController setButtonEnabled:NO];
    });
}

#pragma mark Application Death

- (void)registerApplicationTermination:(void (^)(SUApplicationTerminationStatus))applicationTerminationHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.installingUpdateOnTermination = YES;
        
        // Sudden termination is available on 10.6+
        [[NSProcessInfo processInfo] disableSuddenTermination];
        
        self.applicationTerminationHandler = applicationTerminationHandler;
        
        if (self.handlesTermination) {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
        }
    });
}

- (void)cancelObservingApplicationTermination
{
    if (self.installingUpdateOnTermination) {
        [[NSProcessInfo processInfo] enableSuddenTermination];
        
        if (self.handlesTermination) {
            [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationWillTerminateNotification object:nil];
        }
        
        if (self.applicationTerminationHandler != nil) {
            self.applicationTerminationHandler(SUApplicationStoppedObservingTermination);
            self.applicationTerminationHandler = nil;
        }
        
        self.installingUpdateOnTermination = NO;
    }
}

- (void)unregisterApplicationTermination
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self cancelObservingApplicationTermination];
    });
}

- (void)applicationWillTerminate:(NSNotification *)__unused note
{
    [self sendApplicationTerminationSignal];
}

- (NSApplicationTerminateReply)sendApplicationTerminationSignal
{
    if (self.installingUpdateOnTermination) {
        if (self.applicationTerminationHandler != nil) {
            self.applicationTerminationHandler(SUApplicationWillTerminate);
            self.applicationTerminationHandler = nil;
        }
        
        return NSTerminateLater;
    }
    
    return NSTerminateNow;
}

- (void)terminateApplication
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.installingUpdateOnTermination && !self.handlesTermination) {
            [NSApp replyToApplicationShouldTerminate:YES];
        } else {
            [NSApp terminate:nil];
        }
    });
}

#pragma mark System Death

- (void)registerSystemPowerOff:(void (^)(SUSystemPowerOffStatus))systemPowerOffHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.systemPowerOffHandler = systemPowerOffHandler;
        
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(systemWillPowerOff:) name:NSWorkspaceWillPowerOffNotification object:nil];
    });
}

- (void)cancelObservingSystemPowerOff
{
    if (self.systemPowerOffHandler != nil) {
        self.systemPowerOffHandler(SUStoppedObservingSystemPowerOff);
        self.systemPowerOffHandler = nil;
        
        [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self name:NSWorkspaceWillPowerOffNotification object:nil];
    }
}

- (void)unregisterSystemPowerOff
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self cancelObservingSystemPowerOff];
    });
}

- (void)systemWillPowerOff:(NSNotification *)__unused notification
{
    if (self.systemPowerOffHandler != nil) {
        self.systemPowerOffHandler(SUSystemWillPowerOff);
        self.systemPowerOffHandler = nil;
    }
}

#pragma mark Aborting Update

- (void)dismissUpdateInstallation
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // Make sure everything we call here does not dispatch async to main queue
        // because we are already on the main queue (and I've been bitten in the past by this before)
        
        self.updateInProgress = NO;
        
        [self _invalidateUpdateCheckTimer];
        
        [self cancelCheckForUpdates];
        [self cancelDownload];
        
        if (self.statusController) {
            [self.statusController close];
            self.statusController = nil;
        }
        
        if (self.activeUpdateAlert) {
            [self.activeUpdateAlert close];
            self.activeUpdateAlert = nil;
        }
        
        [self cancelObservingApplicationTermination];
        [self cancelObservingSystemPowerOff];
        [self cancelInstallAndRestart];
    });
}

@end
