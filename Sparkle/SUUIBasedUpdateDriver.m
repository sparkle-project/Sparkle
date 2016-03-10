//
//  SUUIBasedUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/5/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUIBasedUpdateDriver.h"

#import "SUUpdater_Private.h"
#import "SUHost.h"
#import "SUOperatingSystem.h"
#import "SUConstants.h"
#import "SUAppcastItem.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@implementation SUUIBasedUpdateDriver

- (instancetype)initWithUpdater:(SUUpdater *)anUpdater host:(SUHost *)aHost
{
    if ((self = [super initWithUpdater:anUpdater host:aHost])) {
        self.automaticallyInstallUpdates = NO;
    }
    return self;
}

- (void)didFindValidUpdate
{
    if ([[self.updater delegate] respondsToSelector:@selector(updater:didFindValidUpdate:)]) {
        [[self.updater delegate] updater:self.updater didFindValidUpdate:self.updateItem];
    }

    if (self.automaticallyInstallUpdates) {
        [self updateAlertFinishedWithChoice:SUInstallUpdateChoice];
        return;
    }
    
    [self.updater.userDriver showUpdateFoundWithAppcastItem:self.updateItem allowsAutomaticUpdates:self.updater.allowsAutomaticUpdates reply:^(SUUpdateAlertChoice choice) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateAlertFinishedWithChoice:choice];
        });
    }];
}

- (void)didNotFindUpdate
{
    if ([[self.updater delegate] respondsToSelector:@selector(updaterDidNotFindUpdate:)])
        [[self.updater delegate] updaterDidNotFindUpdate:self.updater];
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidNotFindUpdateNotification object:self.updater];

    if (!self.automaticallyInstallUpdates) {
        [self showNotice:^{
            [self.updater.userDriver showUpdateNotFoundWithAcknowledgement:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self abortUpdate];
                });
            }];
        }];
    }
}

- (void)updateAlertFinishedWithChoice:(SUUpdateAlertChoice)choice
{
    [self.host setObject:nil forUserDefaultsKey:SUSkippedVersionKey];
    switch (choice) {
        case SUInstallUpdateChoice:
        {
            [self.updater.userDriver showDownloadInitiatedWithCompletion:^(SUDownloadUpdateStatus downloadCompletionStatus) {
                switch (downloadCompletionStatus) {
                    case SUDownloadUpdateDone:
                        break;
                    case SUDownloadUpdateCancelled:
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (self.download != nil) {
                                if ([[self.updater delegate] respondsToSelector:@selector(userDidCancelDownload:)]) {
                                    [[self.updater delegate] userDidCancelDownload:self.updater];
                                }
                                
                                [self abortUpdate];
                            }
                        });
                        break;
                }
            }];
            
            [self downloadUpdate];
            break;
        }

        case SUSkipThisVersionChoice:
            [self.host setObject:[self.updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
            [self abortUpdate];
            break;

        case SUInstallLaterChoice:
            [self abortUpdate];
            break;
    }
}

- (void)download:(NSURLDownload *)__unused download didReceiveResponse:(NSURLResponse *)response
{
    [self.updater.userDriver showDownloadDidReceiveResponse:response];
}

- (void)download:(NSURLDownload *)__unused download didReceiveDataOfLength:(NSUInteger)length
{
    [self.updater.userDriver showDownloadDidReceiveDataOfLength:length];
}

- (void)extractUpdate
{
    // Now we have to extract the downloaded archive.
    [self.updater.userDriver showDownloadFinishedAndStartedExtractingUpdate];
    
    [super extractUpdate];
}

- (void)unarchiverExtractedProgress:(double)progress
{
    [self.updater.userDriver showExtractionReceivedProgress:progress];
}

- (void)installerDidStart
{
    [self.updater.userDriver showInstallingUpdate];
}

- (void)installerIsReadyForRelaunch
{
    if (self.automaticallyInstallUpdates) {
        [self installWithToolAndRelaunch:YES];
        return;
    }
    
    [self.updater.userDriver showExtractionFinishedAndReadyToInstallAndRelaunch:^(SUInstallUpdateStatus installUpdateStatus) {
        dispatch_async(dispatch_get_main_queue(), ^{
            switch (installUpdateStatus) {
                case SUCancelUpdateInstallation:
                    [self abortUpdate];
                    break;
                case SUInstallAndRelaunchUpdateNow:
                    [self installWithToolAndRelaunch:YES];
                    break;
            }
        });
    }];
}

- (void)installWithToolAndRelaunch:(BOOL)relaunch
{
    //[self.updater.userDriver showInstallingUpdate];
    [super installWithToolAndRelaunch:relaunch];
}

- (void)terminateApp
{
    // if a user chooses to NOT relaunch the app (as is the case with WebKit
    // when it asks you if you are sure you want to close the app with multiple
    // tabs open), the status window still stays on the screen and obscures
    // other windows; with this fix, it doesn't

    [self.updater.userDriver dismissUpdateInstallation];

    [super terminateApp];
}

- (void)abortUpdateWithError:(NSError *)error
{
    [self showNotice:^{
        [self.updater.userDriver showUpdaterError:error acknowledgement:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [super abortUpdateWithError:error];
            });
        }];
    }];
}

// Calling deprecated modal alert methods just to preserve backwards compatibility
- (void)showNotice:(void (^)(void))noticeHandler
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if ([[self.updater delegate] respondsToSelector:@selector(updaterWillShowModalAlert:)]) {
        [[self.updater delegate] updaterWillShowModalAlert:self.updater];
    }
    
    noticeHandler();
    
    if ([[self.updater delegate] respondsToSelector:@selector(updaterDidShowModalAlert:)]) {
        [[self.updater delegate] updaterDidShowModalAlert:self.updater];
    }
#pragma clang diagnostic pop
}

@end
