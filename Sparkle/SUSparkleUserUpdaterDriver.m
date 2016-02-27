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
@property (nonatomic, readonly) BOOL handlesTermination;

@property (nonatomic) SUStatusController *checkingController;
@property (nonatomic, copy) void (^cancelUpdateCheck)(void);

@property (nonatomic) SUWindowController *activeUpdateAlert;

@property (nonatomic) SUStatusController *statusController;
@property (nonatomic, copy) void (^cancelDownload)(void);
@property (nonatomic, copy) void (^installAndRestart)(void);

@property (nonatomic, copy) void (^applicationWillTerminate)(void);
@property (nonatomic, copy) void (^finishTermination)(void);

@end

@implementation SUSparkleUserUpdaterDriver

@synthesize host = _host;
@synthesize handlesTermination = _handlesTermination;
@synthesize delegate = _delegate;
@synthesize checkingController = _checkingController;
@synthesize cancelUpdateCheck = _cancelUpdateCheck;
@synthesize activeUpdateAlert = _activeUpdateAlert;
@synthesize statusController = _statusController;
@synthesize cancelDownload = _cancelDownload;
@synthesize installAndRestart = _installAndRestart;
@synthesize applicationWillTerminate = _applicationWillTerminate;
@synthesize finishTermination = _finishTermination;

- (instancetype)initWithHost:(SUHost *)host handlesTermination:(BOOL)handlesTermination delegate:(id<SUModalAlertDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _host = host;
        _handlesTermination = handlesTermination;
        _delegate = delegate;
    }
    return self;
}

- (void)requestUpdatePermissionWithSystemProfile:(NSArray *)systemProfile reply:(void (^)(SUUpdatePermissionPromptResult *))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // This shows a modal alert dialog which unlike other alerts cannot be closed until the user makes a decision
        // This means that we can never programatically close the dialog if something goes horribly wrong
        // But this dialog should only show up once in the application's lifetime so this may be an OK decision
        [SUUpdatePermissionPrompt promptWithHost:self.host systemProfile:systemProfile reply:reply];
    });
}

- (void)setUpActiveFocusForWindow:(SUWindowController *)updateAlert
{
    // If the app is a menubar app or the like, we need to focus it first and alter the
    // update prompt to behave like a normal window. Otherwise if the window were hidden
    // there may be no way for the application to be activated to make it visible again.
    if ([self.host isBackgroundApplication]) {
        [updateAlert.window setHidesOnDeactivate:NO];
        
        [NSApp activateIgnoringOtherApps:YES];
    }
    
    // We also need to keep the window controller alive until the user makes their decision anyway
    self.activeUpdateAlert = updateAlert;
    
    // Only show the update alert if the app is active; otherwise, we'll wait until it is.
    if ([NSApp isActive])
        [updateAlert.window makeKeyAndOrderFront:self];
    else
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
}

- (void)applicationDidBecomeActive:(NSNotification *)__unused aNotification
{
    [self.activeUpdateAlert.window makeKeyAndOrderFront:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationDidBecomeActiveNotification object:NSApp];
}

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem versionDisplayer:(id<SUVersionDisplay>)versionDisplayer reply:(void (^)(SUUpdateAlertChoice))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        SUUpdateAlert *updateAlert = [[SUUpdateAlert alloc] initWithAppcastItem:appcastItem host:self.host completionBlock:^(SUUpdateAlertChoice choice) {
            reply(choice);
            self.activeUpdateAlert = nil;
        }];
        [updateAlert setVersionDisplayer:versionDisplayer];
        [self setUpActiveFocusForWindow:updateAlert];
    });
}

- (void)showAutomaticUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem reply:(void (^)(SUAutomaticInstallationChoice))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        SUAutomaticUpdateAlert *updateAlert = [[SUAutomaticUpdateAlert alloc] initWithAppcastItem:appcastItem host:self.host completionBlock:^(SUAutomaticInstallationChoice choice) {
            reply(choice);
            self.activeUpdateAlert = nil;
        }];
        
        [self setUpActiveFocusForWindow:updateAlert];
    });
}

- (void)showExtractionFinishedAndReadyToInstallAndRelaunch:(void (^)(void))installUpdateAndRelaunch
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.statusController beginActionWithTitle:SULocalizedString(@"Ready to Install", nil) maxProgressValue:1.0 statusText:nil];
        [self.statusController setProgressValue:1.0]; // Fill the bar.
        [self.statusController setButtonEnabled:YES];
        [self.statusController setButtonTitle:SULocalizedString(@"Install and Relaunch", nil) target:self action:@selector(installAndRestart:) isDefault:YES];
        [[self.statusController window] makeKeyAndOrderFront:self];
        [NSApp requestUserAttention:NSInformationalRequest];
        
        self.installAndRestart = installUpdateAndRelaunch;
    });
}

- (void)installAndRestart:(id)__unused sender
{
    if (self.installAndRestart != nil) {
        self.installAndRestart();
        self.installAndRestart = nil;
    }
}

- (void)showUserInitiatedUpdateCheckWithCancelCallback:(void (^)(void))cancelUpdateCheck
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.cancelUpdateCheck = cancelUpdateCheck;
        
        self.checkingController = [[SUStatusController alloc] initWithHost:self.host];
        [[self.checkingController window] center]; // Force the checking controller to load its window.
        [self.checkingController beginActionWithTitle:SULocalizedString(@"Checking for updates...", nil) maxProgressValue:0.0 statusText:nil];
        [self.checkingController setButtonTitle:SULocalizedString(@"Cancel", nil) target:self action:@selector(cancelCheckForUpdates:) isDefault:NO];
        [self.checkingController showWindow:self];
        
        // For background applications, obtain focus.
        // Useful if the update check is requested from another app like System Preferences.
        if ([self.host isBackgroundApplication])
        {
            [NSApp activateIgnoringOtherApps:YES];
        }
    });
}

- (void)cancelCheckForUpdates:(id)__unused sender
{
    if (self.cancelUpdateCheck != nil) {
        self.cancelUpdateCheck();
        self.cancelUpdateCheck = nil;
    }
}

- (void)dismissUserInitiatedUpdateCheck
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.cancelUpdateCheck = nil;
        
        if (self.checkingController != nil)
        {
            [[self.checkingController window] close];
            self.checkingController = nil;
        }
    });
}

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
        id <SUModalAlertDelegate> delegate = self.delegate;
        
        if ([delegate respondsToSelector:@selector(userUpdaterDriverWillShowModalAlert:)]) {
            [delegate userUpdaterDriverWillShowModalAlert:self];
        }
        
        // When showing a modal alert we need to ensure that background applications
        // are focused to inform the user since there is no dock icon to notify them.
        if ([self.host isBackgroundApplication]) { [NSApp activateIgnoringOtherApps:YES]; }
        
        [alert setIcon:[self.host icon]];
        [alert runModal];
        
        if ([delegate respondsToSelector:@selector(userUpdaterDriverDidShowModalAlert:)]) {
            [delegate userUpdaterDriverDidShowModalAlert:self];
        }
    });
}

- (void)showDownloadInitiatedWithCancelCallback:(void (^)(void))cancelDownload
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.cancelDownload = cancelDownload;
        
        self.statusController = [[SUStatusController alloc] initWithHost:self.host];
        [self.statusController beginActionWithTitle:SULocalizedString(@"Downloading update...", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
        [self.statusController setButtonTitle:SULocalizedString(@"Cancel", nil) target:self action:@selector(cancelDownload:) isDefault:NO];
        [self.statusController showWindow:self];
    });
}

- (void)cancelDownload:(id)__unused sender
{
    if (self.cancelDownload != nil) {
        self.cancelDownload();
        self.cancelDownload = nil;
    }
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

- (void)registerForAppTermination:(void (^)(void))applicationWillTerminate
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // Sudden termination is available on 10.6+
        [[NSProcessInfo processInfo] disableSuddenTermination];
        
        self.applicationWillTerminate = applicationWillTerminate;
        
        if (self.handlesTermination) {
            [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
        }
    });
}

- (void)unregisterForAppTermination
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSProcessInfo processInfo] enableSuddenTermination];
        
        if (self.handlesTermination) {
            [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationWillTerminateNotification object:nil];
        }
        
        self.applicationWillTerminate = nil;
    });
}

- (void)applicationWillTerminate:(NSNotification *)__unused note
{
    // Pass an empty block instead of nil to indicate the app
    // has already initiated termination
    [self sendTerminationSignalWithCompletion:^{}];
}

- (BOOL)isInstallingOnTermination
{
    return (self.applicationWillTerminate != nil);
}

- (void)sendTerminationSignalWithCompletion:(void (^)(void))finishTermination
{
    self.finishTermination = finishTermination;
    
    if (self.applicationWillTerminate) {
        self.applicationWillTerminate();
    }
}

- (void)terminateApplication
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.finishTermination) {
            self.finishTermination();
        } else {
            [NSApp terminate:nil];
        }
    });
}

- (void)dismissUpdateInstallation
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.statusController) {
            [self.statusController close];
            self.statusController = nil;
        }
        
        if (self.activeUpdateAlert) {
            [self.activeUpdateAlert close];
            self.activeUpdateAlert = nil;
        }
        
        self.installAndRestart = nil;
        self.cancelDownload = nil;
        self.cancelUpdateCheck = nil;
    });
}

@end
