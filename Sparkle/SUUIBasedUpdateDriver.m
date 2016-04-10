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
#import "SUErrors.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUUIBasedUpdateDriver() <SUCoreBasedUpdateDriverDelegate>

@property (nonatomic, readonly) SUCoreBasedUpdateDriver *coreDriver;
@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, readonly) BOOL allowsAutomaticUpdates;
@property (nonatomic, weak, readonly) id updater;
@property (weak, nonatomic, readonly) id<SUUpdaterDelegate> updaterDelegate;
@property (nonatomic, weak, readonly) id<SUUIBasedUpdateDriverDelegate> delegate;
@property (nonatomic, readonly) id<SUUserDriver> userDriver;
@property (nonatomic) BOOL resumingUpdate;

@end

@implementation SUUIBasedUpdateDriver

@synthesize coreDriver = _coreDriver;
@synthesize host = _host;
@synthesize allowsAutomaticUpdates = _allowsAutomaticUpdates;
@synthesize updater = _updater;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize userDriver = _userDriver;
@synthesize delegate = _delegate;
@synthesize resumingUpdate = _resumingUpdate;

- (instancetype)initWithHost:(SUHost *)host allowsAutomaticUpdates:(BOOL)allowsAutomaticUpdates sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater userDriver:(id <SUUserDriver>)userDriver updaterDelegate:(nullable id <SUUpdaterDelegate>)updaterDelegate delegate:(id<SUUIBasedUpdateDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _userDriver = userDriver;
        _delegate = delegate;
        _updater = updater;
        _updaterDelegate = updaterDelegate;
        _host = host;
        _allowsAutomaticUpdates = allowsAutomaticUpdates;
        
        _coreDriver = [[SUCoreBasedUpdateDriver alloc] initWithHost:host sparkleBundle:sparkleBundle updater:updater updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders includesSkippedUpdates:(BOOL)includesSkippedUpdates completion:(SUUpdateDriverCompletion)completionBlock
{
    [self.coreDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders includesSkippedUpdates:includesSkippedUpdates completion:completionBlock];
}

- (void)resumeUpdateWithCompletion:(SUUpdateDriverCompletion)completionBlock
{
    self.resumingUpdate = YES;
    [self.coreDriver resumeUpdateWithCompletion:completionBlock];
}

- (void)basicDriverDidFinishLoadingAppcast
{
    if ([self.delegate respondsToSelector:@selector(basicDriverDidFinishLoadingAppcast)]) {
        [self.delegate basicDriverDidFinishLoadingAppcast];
    }
}

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)updateItem
{
    [self.userDriver showUpdateFoundWithAppcastItem:updateItem allowsAutomaticUpdates:self.allowsAutomaticUpdates alreadyDownloaded:self.resumingUpdate reply:^(SUUpdateAlertChoice choice) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateAlertFinishedForUpdateItem:updateItem withChoice:choice];
        });
    }];
}

- (void)updateAlertFinishedForUpdateItem:(SUAppcastItem *)updateItem withChoice:(SUUpdateAlertChoice)choice
{
    [self.host setObject:nil forUserDefaultsKey:SUSkippedVersionKey];
    switch (choice) {
        case SUInstallUpdateChoice:
        {
            if (!self.resumingUpdate) {
                [self.coreDriver downloadUpdateFromAppcastItem:updateItem];
            } else {
                [self.coreDriver finishInstallationWithResponse:SUInstallAndRelaunchUpdateNow];
            }
            break;
        }
            
        case SUSkipThisVersionChoice:
            assert(!self.resumingUpdate);
            [self.host setObject:[updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
            [self.delegate uiDriverIsRequestingAbortUpdateWithError:nil];
            break;
            
        case SUInstallLaterChoice:
            [self.delegate uiDriverIsRequestingAbortUpdateWithError:nil];
            break;
    }
}

- (void)downloadDriverWillBeginDownload
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
}

- (void)downloadDriverDidReceiveResponse:(NSURLResponse *)response
{
    [self.userDriver showDownloadDidReceiveResponse:response];
}

- (void)downloadDriverDidReceiveDataOfLength:(NSUInteger)length
{
    [self.userDriver showDownloadDidReceiveDataOfLength:length];
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

- (void)installerDidFinishPreparationAndCanInstallSilently:(BOOL)__unused canInstallSilently
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

- (BOOL)basicDriverShouldSignalShowingUpdateImmediately
{
    return NO;
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
        
        if (error.code == SUNoUpdateError) {
            [self.userDriver showUpdateNotFoundWithAcknowledgement:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    abortUpdate();
                });
            }];
        } else {
            [self.userDriver showUpdaterError:nonNullError acknowledgement:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    abortUpdate();
                });
            }];
        }
    } else {
        abortUpdate();
    }
}

@end
