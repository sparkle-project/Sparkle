//
//  SUUIBasedUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/5/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUIBasedUpdateDriver.h"

#import "SUUpdateAlert.h"
#import "SUUpdater_Private.h"
#import "SUHost.h"
#import "SUStatusController.h"
#import "SUConstants.h"

@interface SUUIBasedUpdateDriver ()

@property (strong) SUStatusController *statusController;
@property (strong) SUUpdateAlert *updateAlert;

@end

@implementation SUUIBasedUpdateDriver

@synthesize statusController;
@synthesize updateAlert;

- (void)didFindValidUpdate
{
    self.updateAlert = [[SUUpdateAlert alloc] initWithAppcastItem:self.updateItem host:self.host completionBlock:^(SUUpdateAlertChoice choice) {
        [self updateAlertFinishedWithChoice:choice];
    }];

    id<SUVersionDisplay> versDisp = nil;
    if ([[self.updater delegate] respondsToSelector:@selector(versionDisplayerForUpdater:)]) {
        versDisp = [[self.updater delegate] versionDisplayerForUpdater:self.updater];
    }
    [self.updateAlert setVersionDisplayer:versDisp];

    if ([[self.updater delegate] respondsToSelector:@selector(updater:didFindValidUpdate:)]) {
        [[self.updater delegate] updater:self.updater didFindValidUpdate:self.updateItem];
    }

    // If the app is a menubar app or the like, we need to focus it first and alter the
    // update prompt to behave like a normal window. Otherwise if the window were hidden
    // there may be no way for the application to be activated to make it visible again.
    if ([self.host isBackgroundApplication]) {
        [[self.updateAlert window] setHidesOnDeactivate:NO];
        [NSApp activateIgnoringOtherApps:YES];
    }

    // Only show the update alert if the app is active; otherwise, we'll wait until it is.
    if ([NSApp isActive])
        [[self.updateAlert window] makeKeyAndOrderFront:self];
    else
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
}

- (void)didNotFindUpdate
{
    if ([[self.updater delegate] respondsToSelector:@selector(updaterDidNotFindUpdate:)])
        [[self.updater delegate] updaterDidNotFindUpdate:self.updater];
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidNotFindUpdateNotification object:self.updater];

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = SULocalizedString(@"You're up-to-date!", "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
    alert.informativeText = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.", nil), [self.host name], [self.host displayVersion]];
    [alert addButtonWithTitle:SULocalizedString(@"OK", nil)];
    [self showModalAlert:alert];
    [self abortUpdate];
}

- (void)applicationDidBecomeActive:(NSNotification *)__unused aNotification
{
    [[self.updateAlert window] makeKeyAndOrderFront:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationDidBecomeActiveNotification object:NSApp];
}

- (void)updateAlertFinishedWithChoice:(SUUpdateAlertChoice)choice
{
    self.updateAlert = nil;
    [self.host setObject:nil forUserDefaultsKey:SUSkippedVersionKey];
    switch (choice) {
        case SUInstallUpdateChoice:
            self.statusController = [[SUStatusController alloc] initWithHost:self.host];
            [self.statusController beginActionWithTitle:SULocalizedString(@"Downloading update...", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
            [self.statusController setButtonTitle:SULocalizedString(@"Cancel", nil) target:self action:@selector(cancelDownload:) isDefault:NO];
            [self.statusController showWindow:self];
            [self downloadUpdate];
            break;

        case SUOpenInfoURLChoice:
            [[NSWorkspace sharedWorkspace] openURL:[self.updateItem infoURL]];
            [self abortUpdate];
            break;

        case SUSkipThisVersionChoice:
            [self.host setObject:[self.updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
            [self abortUpdate];
            break;

        case SURemindMeLaterChoice:
            [self abortUpdate];
            break;
    }
}

- (void)download:(NSURLDownload *)__unused download didReceiveResponse:(NSURLResponse *)response
{
    [self.statusController setMaxProgressValue:[response expectedContentLength]];
}

- (NSString *)humanReadableSizeFromDouble:(double)value
{
    if (value < 1000) {
        return [NSString stringWithFormat:@"%.0lf %@", value, SULocalizedString(@"B", @"the unit for bytes")];
    }

    if (value < 1000 * 1000) {
        return [NSString stringWithFormat:@"%.0lf %@", value / 1000.0, SULocalizedString(@"KB", @"the unit for kilobytes")];
    }

    if (value < 1000 * 1000 * 1000) {
        return [NSString stringWithFormat:@"%.1lf %@", value / 1000.0 / 1000.0, SULocalizedString(@"MB", @"the unit for megabytes")];
    }

    return [NSString stringWithFormat:@"%.2lf %@", value / 1000.0 / 1000.0 / 1000.0, SULocalizedString(@"GB", @"the unit for gigabytes")];
}

- (void)download:(NSURLDownload *)__unused download didReceiveDataOfLength:(NSUInteger)length
{
    [self.statusController setProgressValue:[self.statusController progressValue] + (double)length];
    if ([self.statusController maxProgressValue] > 0.0)
        [self.statusController setStatusText:[NSString stringWithFormat:SULocalizedString(@"%@ of %@", nil), [self humanReadableSizeFromDouble:[self.statusController progressValue]], [self humanReadableSizeFromDouble:[self.statusController maxProgressValue]]]];
    else
        [self.statusController setStatusText:[NSString stringWithFormat:SULocalizedString(@"%@ downloaded", nil), [self humanReadableSizeFromDouble:[self.statusController progressValue]]]];
}

- (IBAction)cancelDownload:(id)__unused sender
{
    if (self.download)
        [self.download cancel];
    [self abortUpdate];
}

- (void)extractUpdate
{
    // Now we have to extract the downloaded archive.
    [self.statusController beginActionWithTitle:SULocalizedString(@"Extracting update...", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
    [self.statusController setButtonEnabled:NO];
    [super extractUpdate];
}

- (void)unarchiver:(SUUnarchiver *)__unused ua extractedProgress:(double)progress
{
    // We do this here instead of in extractUpdate so that we only have a determinate progress bar for archives with progress.
	if ([self.statusController maxProgressValue] == 0.0) {
        [self.statusController setMaxProgressValue:1];
    }
    [self.statusController setProgressValue:progress];
}

- (void)unarchiverDidFinish:(SUUnarchiver *)__unused ua
{
    [self.statusController beginActionWithTitle:SULocalizedString(@"Ready to Install", nil) maxProgressValue:1.0 statusText:nil];
    [self.statusController setProgressValue:1.0]; // Fill the bar.
    [self.statusController setButtonEnabled:YES];
    [self.statusController setButtonTitle:SULocalizedString(@"Install and Relaunch", nil) target:self action:@selector(installAndRestart:) isDefault:YES];
    [[self.statusController window] makeKeyAndOrderFront:self];
    [NSApp requestUserAttention:NSInformationalRequest];
}

- (void)installAndRestart:(id)__unused sender
{
    [self installWithToolAndRelaunch:YES];
}

- (void)installWithToolAndRelaunch:(BOOL)relaunch
{
    [self.statusController beginActionWithTitle:SULocalizedString(@"Installing update...", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
    [self.statusController setButtonEnabled:NO];
    [super installWithToolAndRelaunch:relaunch];
}

- (void)terminateApp
{
    // if a user chooses to NOT relaunch the app (as is the case with WebKit
    // when it asks you if you are sure you want to close the app with multiple
    // tabs open), the status window still stays on the screen and obscures
    // other windows; with this fix, it doesn't

    if (self.statusController) {
        [self.statusController close];
        self.statusController = nil;
    }

    [super terminateApp];
}

- (void)abortUpdateWithError:(NSError *)error
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = SULocalizedString(@"Update Error!", nil);
    alert.informativeText = [NSString stringWithFormat:@"%@", [error localizedDescription]];
    [alert addButtonWithTitle:SULocalizedString(@"Cancel Update", nil)];
    [self showModalAlert:alert];
    [super abortUpdateWithError:error];
}

- (void)abortUpdate
{
	if (self.statusController)
	{
        [self.statusController close];
        self.statusController = nil;
    }
    [super abortUpdate];
}

- (void)showModalAlert:(NSAlert *)alert
{
    if ([[self.updater delegate] respondsToSelector:@selector(updaterWillShowModalAlert:)]) {
        [[self.updater delegate] updaterWillShowModalAlert:self.updater];
    }

    // When showing a modal alert we need to ensure that background applications
    // are focused to inform the user since there is no dock icon to notify them.
    if ([self.host isBackgroundApplication]) { [NSApp activateIgnoringOtherApps:YES]; }

    [alert setIcon:[self.host icon]];
    [alert runModal];

    if ([[self.updater delegate] respondsToSelector:@selector(updaterDidShowModalAlert:)])
        [[self.updater delegate] updaterDidShowModalAlert:self.updater];
}

@end
