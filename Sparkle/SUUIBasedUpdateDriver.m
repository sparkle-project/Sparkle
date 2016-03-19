//
//  SUUIBasedUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUIBasedUpdateDriver.h"
#import "SUCoreBasedUpdateDriver.h"
#import "SUUserDriver.h"
#import "SUHost.h"
#import "SUConstants.h"
#import "SUUpdaterDelegate.h"
#import "SUAppcastItem.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUUIBasedUpdateDriver() <SUCoreBasedUpdateDriverDelegate>

@property (nonatomic, readonly) SUCoreBasedUpdateDriver *coreDriver;
@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, weak, readonly) id updater;
@property (weak, nonatomic, readonly) id<SUUpdaterDelegate> updaterDelegate;
@property (nonatomic, weak, readonly) id<SUUIBasedUpdateDriverDelegate> delegate;

@end

@implementation SUUIBasedUpdateDriver

@synthesize coreDriver = _coreDriver;
@synthesize host = _host;
@synthesize updater = _updater;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize userDriver = _userDriver;
@synthesize delegate = _delegate;

- (instancetype)initWithHost:(SUHost *)host sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater userDriver:(id <SUUserDriver>)userDriver updaterDelegate:(nullable id <SUUpdaterDelegate>)updaterDelegate delegate:(id<SUUIBasedUpdateDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _userDriver = userDriver;
        _delegate = delegate;
        _updater = updater;
        _updaterDelegate = updaterDelegate;
        _host = host;
        
        _coreDriver = [[SUCoreBasedUpdateDriver alloc] initWithHost:host sparkleBundle:sparkleBundle updater:updater updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders includesSkippedUpdates:(BOOL)includesSkippedUpdates completion:(void (^)(void))completionBlock
{
    [self.coreDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders includesSkippedUpdates:includesSkippedUpdates completion:completionBlock];
}

- (void)basicDriverDidFinishLoadingAppcast
{
    if ([self.delegate respondsToSelector:@selector(basicDriverDidFinishLoadingAppcast)]) {
        [self.delegate basicDriverDidFinishLoadingAppcast];
    }
}

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)updateItem
{
    [self.userDriver showUpdateFoundWithAppcastItem:updateItem allowsAutomaticUpdates:[self allowsAutomaticUpdates] reply:^(SUUpdateAlertChoice choice) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateAlertFinishedForUpdateItem:updateItem withChoice:choice];
            if (choice == SUDownloadUpdateDone) {
                [self.coreDriver downloadUpdateFromAppcastItem:updateItem];
            }
        });
    }];
}

- (BOOL)allowsAutomaticUpdates
{
    // Make sure the host allows automatic updates and
    // make sure we can automatically update in the background without bugging the user (e.g, with a administrator password prompt)
    return (self.host.allowsAutomaticUpdates && [[NSFileManager defaultManager] isWritableFileAtPath:self.host.bundlePath]);
}

- (void)updateAlertFinishedForUpdateItem:(SUAppcastItem *)updateItem withChoice:(SUUpdateAlertChoice)choice
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
                            if ([self.updaterDelegate respondsToSelector:@selector(userDidCancelDownload:)]) {
                                [self.updaterDelegate userDidCancelDownload:self.updater];
                            }
                            
                            [self.delegate uiDriverIsRequestingAbortUpdateWithError:nil];
                        });
                        break;
                }
            }];
            break;
        }
            
        case SUSkipThisVersionChoice:
            [self.host setObject:[updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
            [self.delegate uiDriverIsRequestingAbortUpdateWithError:nil];
            break;
            
        case SUInstallLaterChoice:
            [self.delegate uiDriverIsRequestingAbortUpdateWithError:nil];
            break;
    }
}

- (void)coreDriverDidFinishDownloadingUpdate
{
    [self.userDriver showDownloadFinishedAndStartedExtractingUpdate];
}

- (void)installerDidStartInstalling
{
    [self.userDriver showInstallingUpdate];
}

- (void)installerDidExtractUpdateWithProgress:(double)progress
{
    [self.userDriver showExtractionReceivedProgress:progress];
}

- (void)installerDidFinishRelaunchPreparation
{
    [self.userDriver showExtractionFinishedAndReadyToInstallAndRelaunch:^(SUInstallUpdateStatus installUpdateStatus) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.coreDriver finishInstallationWithResponse:installUpdateStatus];
        });
    }];
}

- (void)coreDriverIsRequestingAppTermination
{
    // if a user chooses to NOT relaunch the app (as is the case with WebKit
    // when it asks you if you are sure you want to close the app with multiple
    // tabs open), the status window still stays on the screen and obscures
    // other windows; with this fix, it doesn't
    [self.userDriver dismissUpdateInstallation];
    
    [self.userDriver terminateApplication];
}

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    // A delegate may want to handle this type of error specially
    [self.delegate basicDriverIsRequestingAbortUpdateWithError:error];
}

- (void)coreDriverIsRequestingAbortUpdateWithError:(NSError *)error
{
    [self.delegate uiDriverIsRequestingAbortUpdateWithError:error];
}

- (void)abortUpdateWithError:(nullable NSError *)error
{
    void (^abortUpdate)(void) = ^{
        [self.coreDriver abortUpdateWithError:error];
        [self.userDriver dismissUpdateInstallation];
    };
    
    if (error != nil) {
        NSError *nonNullError = error;
        [self.userDriver showUpdaterError:nonNullError acknowledgement:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                abortUpdate();
            });
        }];
    } else {
        abortUpdate();
    }
}

@end
