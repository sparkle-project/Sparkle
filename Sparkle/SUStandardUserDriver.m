//
//  SUStandardUserDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/14/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUStandardUserDriver.h"
#import "SUUserDriverCoreComponent.h"
#import "SUUserDriverUIComponent.h"
#import "SUStandardUserDriverDelegate.h"
#import "SUStandardUserDriverUIDelegate.h"
#import "SUAppcastItem.h"
#import "SUVersionDisplayProtocol.h"
#import "SUHost.h"
#import "SUUpdatePermissionPrompt.h"
#import "SUStatusController.h"
#import "SUUpdateAlert.h"
#import "SUAutomaticUpdateAlert.h"
#import "SULocalizations.h"
#import "SUApplicationInfo.h"

@interface SUStandardUserDriver ()

@property (nonatomic, readonly) SUHost *host;

@property (nonatomic, readonly) SUUserDriverCoreComponent *coreComponent;
@property (nonatomic, readonly) SUUserDriverUIComponent *uiComponent;

@property (nonatomic) SUStatusController *checkingController;
@property (nonatomic) NSWindowController *activeUpdateAlert;
@property (nonatomic) SUStatusController *statusController;

@end

@implementation SUStandardUserDriver

@synthesize host = _host;
@synthesize coreComponent = _coreComponent;
@synthesize uiComponent = _uiComponent;
@synthesize delegate = _delegate;
@synthesize checkingController = _checkingController;
@synthesize activeUpdateAlert = _activeUpdateAlert;
@synthesize statusController = _statusController;

#pragma mark Birth

- (instancetype)initWithHostBundle:(NSBundle *)hostBundle delegate:(id<SUStandardUserDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _host = [[SUHost alloc] initWithBundle:hostBundle];
        _delegate = delegate;
        _coreComponent = [[SUUserDriverCoreComponent alloc] initWithUserDriver:self delegate:delegate];
        _uiComponent = [[SUUserDriverUIComponent alloc] initWithUserDriver:self delegate:delegate];
    }
    return self;
}

#pragma mark Is Update Busy?

- (void)idleOnUpdateChecks:(BOOL)shouldIdleOnUpdateChecks
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent idleOnUpdateChecks:shouldIdleOnUpdateChecks];
    });
}

- (BOOL)idlesOnUpdateChecks
{
    return self.coreComponent.idlesOnUpdateChecks;
}

- (void)showUpdateInProgress:(BOOL)isUpdateInProgress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent showUpdateInProgress:isUpdateInProgress];
    });
}

- (BOOL)isUpdateInProgress
{
    return self.coreComponent.updateInProgress;
}

#pragma mark Check Updates Timer

- (BOOL)willInitiateNextUpdateCheck
{
    return [self.coreComponent willInitiateNextUpdateCheck];
}

- (void)startUpdateCheckTimerWithNextTimeInterval:(NSTimeInterval)timeInterval reply:(void (^)(SUUpdateCheckTimerStatus))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent startUpdateCheckTimerWithNextTimeInterval:timeInterval reply:reply];
    });
}

- (void)invalidateUpdateCheckTimer
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent invalidateUpdateCheckTimer];
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

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem allowsAutomaticUpdates:(BOOL)allowsAutomaticUpdates reply:(void (^)(SUUpdateAlertChoice))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        id <SUVersionDisplay> versionDisplayer = nil;
        if ([self.delegate respondsToSelector:@selector(versionDisplayerForUserDriver:)]) {
            versionDisplayer = [self.delegate versionDisplayerForUserDriver:self];
        }
        
        __weak SUStandardUserDriver *weakSelf = self;
        self.activeUpdateAlert = [[SUUpdateAlert alloc] initWithAppcastItem:appcastItem host:self.host versionDisplayer:versionDisplayer allowsAutomaticUpdates:allowsAutomaticUpdates completionBlock:^(SUUpdateAlertChoice choice) {
            reply(choice);
            weakSelf.activeUpdateAlert = nil;
        }];
        
        [self setUpFocusForActiveUpdateAlert];
    });
}

- (void)showAutomaticUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem reply:(void (^)(SUUpdateAlertChoice))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        __weak SUStandardUserDriver *weakSelf = self;
        self.activeUpdateAlert = [[SUAutomaticUpdateAlert alloc] initWithAppcastItem:appcastItem host:self.host completionBlock:^(SUUpdateAlertChoice choice) {
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
        
        [self.coreComponent registerInstallUpdateHandler:installUpdateHandler];
    });
}

- (void)installAndRestart:(id)__unused sender
{
    [self.coreComponent installAndRestart];
}

#pragma mark Check for Updates

- (void)showUserInitiatedUpdateCheckWithCompletion:(void (^)(SUUserInitiatedCheckStatus))updateCheckStatusCompletion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent registerUpdateCheckStatusHandler:updateCheckStatusCompletion];
        
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

- (void)closeCheckingWindow
{
    if (self.checkingController != nil)
    {
        [[self.checkingController window] close];
        self.checkingController = nil;
    }
}

- (void)cancelCheckForUpdates:(id)__unused sender
{
    [self.coreComponent cancelUpdateCheckStatus];
    [self closeCheckingWindow];
}

- (void)dismissUserInitiatedUpdateCheck
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent completeUpdateCheckStatus];
        [self closeCheckingWindow];
    });
}

#pragma mark Update Errors

- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent registerAcknowledgement:acknowledgement];
        
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = SULocalizedString(@"Update Error!", nil);
        alert.informativeText = [NSString stringWithFormat:@"%@", [error localizedDescription]];
        [alert addButtonWithTitle:SULocalizedString(@"Cancel Update", nil)];
        [self showAlert:alert];
        
        [self.coreComponent acceptAcknowledgement];
    });
}

- (void)showUpdateNotFoundWithAcknowledgement:(void (^)(void))acknowledgement
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent registerAcknowledgement:acknowledgement];
        
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = SULocalizedString(@"You're up-to-date!", "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
        alert.informativeText = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.", nil), [self.host name], [self.host displayVersion]];
        [alert addButtonWithTitle:SULocalizedString(@"OK", nil)];
        [self showAlert:alert];
        
        [self.coreComponent acceptAcknowledgement];
    });
}

- (void)showAlert:(NSAlert *)alert
{
    dispatch_async(dispatch_get_main_queue(), ^{
        id <SUStandardUserDriverDelegate> delegate = self.delegate;
        
        if ([delegate respondsToSelector:@selector(userDriverWillShowModalAlert:)]) {
            [delegate userDriverWillShowModalAlert:self];
        }
        
        // When showing a modal alert we need to ensure that background applications
        // are focused to inform the user since there is no dock icon to notify them.
        if ([SUApplicationInfo isBackgroundApplication:NSApp]) { [NSApp activateIgnoringOtherApps:YES]; }
        
        [alert setIcon:[SUApplicationInfo bestIconForBundle:self.host.bundle]];
        [alert runModal];
        
        if ([delegate respondsToSelector:@selector(userDriverDidShowModalAlert:)]) {
            [delegate userDriverDidShowModalAlert:self];
        }
    });
}

#pragma mark Download & Install Updates

- (void)showDownloadInitiatedWithCompletion:(void (^)(SUDownloadUpdateStatus))downloadUpdateStatusCompletion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent registerDownloadStatusHandler:downloadUpdateStatusCompletion];
        
        self.statusController = [[SUStatusController alloc] initWithHost:self.host];
        [self.statusController beginActionWithTitle:SULocalizedString(@"Downloading update...", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
        [self.statusController setButtonTitle:SULocalizedString(@"Cancel", nil) target:self action:@selector(cancelDownload:) isDefault:NO];
        [self.statusController showWindow:self];
    });
}

- (void)cancelDownload:(id)__unused sender
{
    [self.coreComponent cancelDownloadStatus];
}

- (void)showDownloadDidReceiveResponse:(NSURLResponse *)response
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.statusController setMaxProgressValue:[response expectedContentLength]];
    });
}

- (NSString *)localizedStringFromByteCount:(long long)value
{
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
        [self.coreComponent completeDownloadStatus];
        
        [self.statusController beginActionWithTitle:SULocalizedString(@"Extracting update...", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
        [self.statusController setButtonEnabled:NO];
    });
}

- (void)showExtractionReceivedProgress:(double)progress
{
    dispatch_async(dispatch_get_main_queue(), ^{
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
        [self.uiComponent registerApplicationTermination:applicationTerminationHandler];
    });
}

- (void)unregisterApplicationTermination
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.uiComponent unregisterApplicationTermination];
    });
}

- (NSApplicationTerminateReply)sendApplicationTerminationSignal
{
    return [self.uiComponent sendApplicationTerminationSignal];
}

- (void)terminateApplication
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.uiComponent terminateApplication];
    });
}

#pragma mark System Death

- (void)registerSystemPowerOff:(void (^)(SUSystemPowerOffStatus))systemPowerOffHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.uiComponent registerSystemPowerOff:systemPowerOffHandler];
    });
}

- (void)unregisterSystemPowerOff
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.uiComponent unregisterSystemPowerOff];
    });
}

#pragma mark Aborting Everything

- (void)_dismissUpdateInstallation
{
    // Make sure everything we call here does not dispatch async to main queue
    // because we are already on the main queue (and I've been bitten in the past by this before)
    
    [self.coreComponent dismissUpdateInstallation];
    [self.uiComponent dismissUpdateInstallation];
    
    [self closeCheckingWindow];
    
    if (self.statusController) {
        [self.statusController close];
        self.statusController = nil;
    }
    
    if (self.activeUpdateAlert) {
        [self.activeUpdateAlert close];
        self.activeUpdateAlert = nil;
    }
}

- (void)dismissUpdateInstallation
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _dismissUpdateInstallation];
    });
}

- (void)invalidate
{
    // Make sure any remote handlers will not be invoked
    [self.coreComponent invalidate];
    [self.uiComponent invalidate];
    
    // Dismiss the installation normally
    [self _dismissUpdateInstallation];
}

@end
