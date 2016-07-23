//
//  SUAutomaticUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUAutomaticUpdateDriver.h"
#import "SUUpdateDriver.h"
#import "SUHost.h"
#import "SUUpdaterDelegate.h"
#import "SUCoreBasedUpdateDriver.h"
#import "SULog.h"
#import "SUAppcastItem.h"
#import "SUErrors.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUAutomaticUpdateDriver () <SUCoreBasedUpdateDriverDelegate>

@property (nonatomic, readonly, weak) id updater;
@property (nonatomic, readonly, weak, nullable) id updaterDelegate;
@property (nonatomic, readonly) SUCoreBasedUpdateDriver *coreDriver;
@property (nonatomic) SUAppcastItem* updateItem;
@property (nonatomic) BOOL willInstallSilently;

@end

@implementation SUAutomaticUpdateDriver

@synthesize updater = _updater;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize coreDriver = _coreDriver;
@synthesize updateItem = _updateItem;
@synthesize willInstallSilently = _willInstallSilently;

- (instancetype)initWithHost:(SUHost *)host sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater updaterDelegate:(nullable id <SUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _updater = updater;
        _updaterDelegate = updaterDelegate;
        _coreDriver = [[SUCoreBasedUpdateDriver alloc] initWithHost:host sparkleBundle:sparkleBundle updater:updater updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders completion:(SUUpdateDriverCompletion)completionBlock
{
    [self.coreDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders includesSkippedUpdates:NO requiresSilentInstall:YES completion:completionBlock];
}

- (void)resumeUpdateWithCompletion:(SUUpdateDriverCompletion)__unused completionBlock __attribute__((noreturn))
{
    // Nothing really to do here.. this shouldn't be called.
    SULog(@"Error: resumeUpdateWithCompletion: called on SUAutomaticUpdateDriver");
    abort();
}

- (void)resumeDownloadedUpdate:(SUDownloadedUpdate *)__unused downloadedUpdate completion:(SUUpdateDriverCompletion)__unused completionBlock __attribute__((noreturn))
{
    // Nothing really to do here.. this shouldn't be called.
    SULog(@"Error: resumeDownloadedUpdate:completion: called on SUAutomaticUpdateDriver");
    abort();
}

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)updateItem
{
    self.updateItem = updateItem;
    
    [self.coreDriver downloadUpdateFromAppcastItem:updateItem];
}

- (void)installerDidFinishPreparationAndWillInstallImmediately:(BOOL)willInstallImmediately silently:(BOOL)willInstallSilently
{
    self.willInstallSilently = willInstallSilently;
    
    if (!willInstallImmediately) {
        BOOL installationHandledByDelegate = NO;
        id<SUUpdaterDelegate> updaterDelegate = self.updaterDelegate;
        if (self.willInstallSilently && [updaterDelegate respondsToSelector:@selector(updater:willInstallUpdateOnQuit:immediateInstallationBlock:)]) {
            __weak SUAutomaticUpdateDriver *weakSelf = self;
            installationHandledByDelegate =
            [updaterDelegate updater:self.updater willInstallUpdateOnQuit:self.updateItem immediateInstallationBlock:^{
                [weakSelf.coreDriver finishInstallationWithResponse:SUInstallAndRelaunchUpdateNow displayingUserInterface:NO];
            }];
        }
        
        if (!installationHandledByDelegate) {
            // We are done and can safely abort now
            // The installer tool will keep the installation alive
            [self abortUpdate];
        }
    }
}

// This can only be reached if the updater delegate invokes its immediate installation block above,
// otherwise the update driver will abort the update before then
- (void)installerIsRequestingAppTermination
{
    id<SUUpdaterDelegate> updaterDelegate = self.updaterDelegate;
    if ([updaterDelegate respondsToSelector:@selector(updaterIsRequestingQuit:)]) {
        [updaterDelegate updaterIsRequestingQuit:self.updater];
    }
}

- (void)basicDriverIsRequestingAbortUpdateWithError:(NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)coreDriverIsRequestingAbortUpdateWithError:(NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)abortUpdate
{
    [self abortUpdateWithError:nil];
}

- (void)abortUpdateWithError:(NSError *)error
{
    BOOL showNextUpdateImmediately = (error == nil || error.code == SUInstallationTryAgainLaterError) && (!self.willInstallSilently || self.updateItem.isCriticalUpdate);
    [self.coreDriver abortUpdateAndShowNextUpdateImmediately:showNextUpdateImmediately error:error];
}

@end
