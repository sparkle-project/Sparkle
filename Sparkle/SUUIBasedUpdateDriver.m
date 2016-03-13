//
//  SUUIBasedUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/5/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUIBasedUpdateDriver.h"
#import "SUUpdaterDelegate.h"
#import "SUUserDriver.h"
#import "SUHost.h"
#import "SUConstants.h"
#import "SUAppcastItem.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@implementation SUUIBasedUpdateDriver

- (instancetype)initWithUpdater:(id)anUpdater updaterDelegate:(id<SUUpdaterDelegate>)updaterDelegate userDriver:(id<SUUserDriver>)userDriver host:(SUHost *)host sparkleBundle:(NSBundle *)sparkleBundle
{
    if ((self = [super initWithUpdater:anUpdater updaterDelegate:updaterDelegate userDriver:userDriver host:host sparkleBundle:sparkleBundle])) {
        self.automaticallyInstallUpdates = NO;
    }
    return self;
}

// This indicates if automatic updates are allowed even if they may not be turned on at the moment
- (BOOL)allowsAutomaticUpdates
{
    // Make sure the host allows automatic updates and
    // make sure we can automatically update in the background without bugging the user (e.g, with a administrator password prompt)
    return (self.host.allowsAutomaticUpdates && [[NSFileManager defaultManager] isWritableFileAtPath:self.host.bundlePath]);
}

- (void)didFindValidUpdate
{
    if ([self.updaterDelegate respondsToSelector:@selector(updater:didFindValidUpdate:)]) {
        [self.updaterDelegate updater:self.updater didFindValidUpdate:self.updateItem];
    }

    if (self.automaticallyInstallUpdates) {
        [self updateAlertFinishedWithChoice:SUInstallUpdateChoice];
        return;
    }
    
    [self.userDriver showUpdateFoundWithAppcastItem:self.updateItem allowsAutomaticUpdates:[self allowsAutomaticUpdates] reply:^(SUUpdateAlertChoice choice) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateAlertFinishedWithChoice:choice];
        });
    }];
}

- (void)didNotFindUpdate
{
    if ([self.updaterDelegate respondsToSelector:@selector(updaterDidNotFindUpdate:)])
        [self.updaterDelegate updaterDidNotFindUpdate:self.updater];
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidNotFindUpdateNotification object:self.updater];

    if (!self.automaticallyInstallUpdates) {
        [self showNotice:^{
            [self.userDriver showUpdateNotFoundWithAcknowledgement:^{
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
            [self.userDriver showDownloadInitiatedWithCompletion:^(SUDownloadUpdateStatus downloadCompletionStatus) {
                switch (downloadCompletionStatus) {
                    case SUDownloadUpdateDone:
                        break;
                    case SUDownloadUpdateCancelled:
                        dispatch_async(dispatch_get_main_queue(), ^{
                            if (self.download != nil) {
                                if ([self.updaterDelegate respondsToSelector:@selector(userDidCancelDownload:)]) {
                                    [self.updaterDelegate userDidCancelDownload:self.updater];
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
    [self.userDriver showDownloadDidReceiveResponse:response];
}

- (void)download:(NSURLDownload *)__unused download didReceiveDataOfLength:(NSUInteger)length
{
    [self.userDriver showDownloadDidReceiveDataOfLength:length];
}

- (void)extractUpdate
{
    // Now we have to extract the downloaded archive.
    [self.userDriver showDownloadFinishedAndStartedExtractingUpdate];
    
    [super extractUpdate];
}

- (void)unarchiverExtractedProgress:(double)progress
{
    [self.userDriver showExtractionReceivedProgress:progress];
}

- (void)installerDidStart
{
    [self.userDriver showInstallingUpdate];
}

- (void)installerIsReadyForRelaunch
{
    if (self.automaticallyInstallUpdates) {
        [self installWithToolAndRelaunch:YES];
        return;
    }
    
    [self.userDriver showExtractionFinishedAndReadyToInstallAndRelaunch:^(SUInstallUpdateStatus installUpdateStatus) {
        dispatch_async(dispatch_get_main_queue(), ^{
            switch (installUpdateStatus) {
                case SUDismissUpdateInstallation:
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

    [self.userDriver dismissUpdateInstallation];

    [super terminateApp];
}

- (void)abortUpdateWithError:(NSError *)error
{
    [self showNotice:^{
        [self.userDriver showUpdaterError:error acknowledgement:^{
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
    if ([self.updaterDelegate respondsToSelector:@selector(updaterWillShowModalAlert:)]) {
        [self.updaterDelegate updaterWillShowModalAlert:self.updater];
    }
    
    noticeHandler();
    
    if ([self.updaterDelegate respondsToSelector:@selector(updaterDidShowModalAlert:)]) {
        [self.updaterDelegate updaterDidShowModalAlert:self.updater];
    }
#pragma clang diagnostic pop
}

@end
