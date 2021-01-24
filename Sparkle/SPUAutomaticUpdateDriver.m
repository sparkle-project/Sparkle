//
//  SPUAutomaticUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUAutomaticUpdateDriver.h"
#import "SPUUpdateDriver.h"
#import "SUHost.h"
#import "SPUUpdaterDelegate.h"
#import "SPUCoreBasedUpdateDriver.h"
#import "SULog.h"
#import "SUAppcastItem.h"
#import "SPUUserDriver.h"
#import "SUErrors.h"


#include "AppKitPrevention.h"

@interface SPUAutomaticUpdateDriver () <SPUCoreBasedUpdateDriverDelegate>

@property (nonatomic, readonly, weak) id updater;
@property (nonatomic, readonly, weak) id<SPUUserDriver> userDriver;
@property (nonatomic, readonly, weak, nullable) id updaterDelegate;
@property (nonatomic, readonly) SPUCoreBasedUpdateDriver *coreDriver;
@property (nonatomic) SUAppcastItem* updateItem;
@property (nonatomic) BOOL willInstallSilently;

@end

@implementation SPUAutomaticUpdateDriver

@synthesize updater = _updater;
@synthesize userDriver = _userDriver;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize coreDriver = _coreDriver;
@synthesize updateItem = _updateItem;
@synthesize willInstallSilently = _willInstallSilently;

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _updater = updater;
        // The user driver is only used for a termination callback
        _userDriver = userDriver;
        _updaterDelegate = updaterDelegate;
        _coreDriver = [[SPUCoreBasedUpdateDriver alloc] initWithHost:host applicationBundle:applicationBundle sparkleBundle:sparkleBundle updater:updater updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders preventingInstallerInteraction:(BOOL)preventsInstallerInteraction completion:(SPUUpdateDriverCompletion)completionBlock
{
    [self.coreDriver prepareCheckForUpdatesWithCompletion:completionBlock];
    
    [self.coreDriver preflightForUpdatePermissionPreventingInstallerInteraction:preventsInstallerInteraction reply:^(NSError * _Nullable error) {
        if (error != nil) {
            [self abortUpdateWithError:error];
        } else {
            [self.coreDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders inBackground:YES includesSkippedUpdates:NO requiresSilentInstall:YES];
        }
    }];
}

- (void)resumeInstallingUpdateWithCompletion:(SPUUpdateDriverCompletion)__unused completionBlock
{
    // Nothing really to do here.. this shouldn't be called.
    SULog(SULogLevelError, @"Error: resumeInstallingUpdateWithCompletion: called on SPUAutomaticUpdateDriver");
}

- (void)resumeUpdate:(id<SPUResumableUpdate>)__unused resumableUpdate completion:(SPUUpdateDriverCompletion)__unused completionBlock
{
    // Nothing really to do here.. this shouldn't be called.
    SULog(SULogLevelError, @"Error: resumeDownloadedUpdate:completion: called on SPUAutomaticUpdateDriver");
}

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)updateItem preventsAutoupdate:(BOOL)preventsAutoupdate
{
    self.updateItem = updateItem;
    
    if (updateItem.isInformationOnlyUpdate || preventsAutoupdate) {
        [self.coreDriver deferInformationalUpdate:updateItem preventsAutoupdate:preventsAutoupdate];
        [self abortUpdate];
    } else {
        [self.coreDriver downloadUpdateFromAppcastItem:updateItem inBackground:YES];
    }
}

- (void)installerDidFinishPreparationAndWillInstallImmediately:(BOOL)willInstallImmediately silently:(BOOL)willInstallSilently
{
    self.willInstallSilently = willInstallSilently;
    
    if (!willInstallImmediately) {
        BOOL installationHandledByDelegate = NO;
        id<SPUUpdaterDelegate> updaterDelegate = self.updaterDelegate;
        if (self.willInstallSilently && [updaterDelegate respondsToSelector:@selector(updater:willInstallUpdateOnQuit:immediateInstallationBlock:)]) {
            __weak SPUAutomaticUpdateDriver *weakSelf = self;
            installationHandledByDelegate = [updaterDelegate updater:self.updater willInstallUpdateOnQuit:self.updateItem immediateInstallationBlock:^{
                [weakSelf.coreDriver finishInstallationWithResponse:SPUInstallAndRelaunchUpdateNow displayingUserInterface:NO];
            }];
        }
        
        if (!installationHandledByDelegate) {
            // We are done and can safely abort now
            // The installer tool will keep the installation alive
            [self abortUpdate];
        }
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
    BOOL showNextUpdateImmediately = (error == nil || error.code == SUInstallationAuthorizeLaterError) && (!self.willInstallSilently || self.updateItem.isCriticalUpdate || self.updateItem.isInformationOnlyUpdate);
    [self.coreDriver abortUpdateAndShowNextUpdateImmediately:showNextUpdateImmediately error:error];
}

@end
