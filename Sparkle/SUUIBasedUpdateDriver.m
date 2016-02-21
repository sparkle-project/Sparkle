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

@implementation SUUIBasedUpdateDriver

- (instancetype)initWithUpdater:(SUUpdater *)anUpdater
{
    if ((self = [super initWithUpdater:anUpdater])) {
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
    
    id<SUVersionDisplay> versDisp = nil;
    if ([[self.updater delegate] respondsToSelector:@selector(versionDisplayerForUpdater:)]) {
        versDisp = [[self.updater delegate] versionDisplayerForUpdater:self.updater];
    }
    
    [self.updater.userUpdaterDriver showUpdateFoundWithAppcastItem:self.updateItem versionDisplayer:versDisp reply:^(SUUpdateAlertChoice choice) {
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
        [self showNoticeModally:[self.updater.userUpdaterDriver showsUpdateNotFoundModally] noticeHandler:^{
            [self.updater.userUpdaterDriver showUpdateNotFound];
        }];
        
        [self abortUpdate];
    }
}

- (void)updateAlertFinishedWithChoice:(SUUpdateAlertChoice)choice
{
    [self.host setObject:nil forUserDefaultsKey:SUSkippedVersionKey];
    switch (choice) {
        case SUInstallUpdateChoice:
        {
            [self.updater.userUpdaterDriver showDownloadInitiatedWithCancelCallback:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.download) {
                        [self.download cancel];
                        if ([[self.updater delegate] respondsToSelector:@selector(userDidCancelDownload:)]) {
                            [[self.updater delegate] userDidCancelDownload:self.updater];
                        }
                    }
                    [self abortUpdate];
                });
            }];
            
            [self downloadUpdate];
            break;
        }

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
    [self.updater.userUpdaterDriver showDownloadDidReceiveResponse:response];
}

- (void)download:(NSURLDownload *)__unused download didReceiveDataOfLength:(NSUInteger)length
{
    [self.updater.userUpdaterDriver showDownloadDidReceiveDataOfLength:length];
}

- (void)extractUpdate
{
    // Now we have to extract the downloaded archive.
    [self.updater.userUpdaterDriver showDownloadFinishedAndStartedExtractingUpdate];
    
    [super extractUpdate];
}

- (void)unarchiver:(SUUnarchiver *)__unused ua extractedProgress:(double)progress
{
    [self.updater.userUpdaterDriver showExtractionReceivedProgress:progress];
}

- (void)unarchiverDidFinish:(SUUnarchiver *)__unused ua
{
    if (self.automaticallyInstallUpdates) {
        [self installWithToolAndRelaunch:YES];
        return;
    }
    
    [self.updater.userUpdaterDriver showExtractionFinishedAndReadyToInstallAndRelaunch:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self installWithToolAndRelaunch:YES];
        });
    }];
}

- (void)installWithToolAndRelaunch:(BOOL)relaunch
{
    [self.updater.userUpdaterDriver showInstallingUpdate];
    
    [super installWithToolAndRelaunch:relaunch];
}

- (void)terminateApp
{
    // if a user chooses to NOT relaunch the app (as is the case with WebKit
    // when it asks you if you are sure you want to close the app with multiple
    // tabs open), the status window still stays on the screen and obscures
    // other windows; with this fix, it doesn't

    [self.updater.userUpdaterDriver dismissUpdateInstallation:SUManualInstallationType];

    [super terminateApp];
}

- (void)abortUpdateWithError:(NSError *)error
{
    [self showNoticeModally:[self.updater.userUpdaterDriver showsUpdateErrorModally] noticeHandler:^{
        [self.updater.userUpdaterDriver showUpdaterError:error];
    }];
    
    [super abortUpdateWithError:error];
}

- (void)abortUpdate
{
    [self.updater.userUpdaterDriver dismissUpdateInstallation:SUManualInstallationType];
    
    [super abortUpdate];
}

- (void)showNoticeModally:(BOOL)modally noticeHandler:(void (^)(void))noticeHandler
{
    if (modally && [[self.updater delegate] respondsToSelector:@selector(updaterWillShowModalAlert:)]) {
        [[self.updater delegate] updaterWillShowModalAlert:self.updater];
    }
    
    noticeHandler();
    
    if (modally && [[self.updater delegate] respondsToSelector:@selector(updaterDidShowModalAlert:)]) {
        [[self.updater delegate] updaterDidShowModalAlert:self.updater];
    }
}

@end
