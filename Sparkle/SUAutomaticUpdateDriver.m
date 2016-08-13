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
#import "SPUUserDriver.h"
#import "SUErrors.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUAutomaticUpdateDriver () <SUCoreBasedUpdateDriverDelegate>

@property (nonatomic, readonly, weak) id updater;
@property (nonatomic, readonly, weak) id<SPUUserDriver> userDriver;
@property (nonatomic, readonly, weak, nullable) id updaterDelegate;
@property (nonatomic, readonly) SUCoreBasedUpdateDriver *coreDriver;
@property (nonatomic) SUAppcastItem* updateItem;
@property (nonatomic) BOOL willInstallSilently;

@end

@implementation SUAutomaticUpdateDriver

@synthesize updater = _updater;
@synthesize userDriver = _userDriver;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize coreDriver = _coreDriver;
@synthesize updateItem = _updateItem;
@synthesize willInstallSilently = _willInstallSilently;

- (instancetype)initWithHost:(SUHost *)host sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver updaterDelegate:(nullable id <SUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _updater = updater;
        // The user driver is only used for a termination callback
        _userDriver = userDriver;
        _updaterDelegate = updaterDelegate;
        _coreDriver = [[SUCoreBasedUpdateDriver alloc] initWithHost:host sparkleBundle:sparkleBundle updater:updater updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders completion:(SUUpdateDriverCompletion)completionBlock
{
    [self.coreDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders includesSkippedUpdates:NO requiresSilentInstall:YES completion:completionBlock];
}

- (void)resumeInstallingUpdateWithCompletion:(SUUpdateDriverCompletion)__unused completionBlock __attribute__((noreturn))
{
    // Nothing really to do here.. this shouldn't be called.
    SULog(@"Error: resumeInstallingUpdateWithCompletion: called on SUAutomaticUpdateDriver");
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

// Method used for backwards compatibility for the updater delegate
- (void)finishInstallationAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showingUI
{
    [self.coreDriver finishInstallationWithResponse:(relaunch ? SPUInstallAndRelaunchUpdateNow : SPUInstallUpdateNow) displayingUserInterface:showingUI];
}

- (void)installerDidFinishPreparationAndWillInstallImmediately:(BOOL)willInstallImmediately silently:(BOOL)willInstallSilently
{
    self.willInstallSilently = willInstallSilently;
    
    if (!willInstallImmediately) {
        BOOL installationHandledByDelegate = NO;
        id<SUUpdaterDelegate> updaterDelegate = self.updaterDelegate;
        if (self.willInstallSilently) {
            if ([updaterDelegate respondsToSelector:@selector(updater:willInstallUpdateOnQuit:immediateInstallationBlock:)]) {
                __weak SUAutomaticUpdateDriver *weakSelf = self;
                installationHandledByDelegate = [updaterDelegate updater:self.updater willInstallUpdateOnQuit:self.updateItem immediateInstallationBlock:^{
                    [weakSelf.coreDriver finishInstallationWithResponse:SPUInstallAndRelaunchUpdateNow displayingUserInterface:NO];
                }];
            } else if ([updaterDelegate respondsToSelector:@selector(updater:willInstallUpdateOnQuit:immediateInstallationInvocation:)]) {
                // Just for backwards compatibility
                
                BOOL relaunch = YES;
                BOOL showUI = NO;
                
                NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:@selector(finishInstallationAndRelaunch:displayingUserInterface:)]];
                [invocation setSelector:@selector(finishInstallationAndRelaunch:displayingUserInterface:)];
                [invocation setArgument:&relaunch atIndex:2];
                [invocation setArgument:&showUI atIndex:3];
                [invocation setTarget:self];
                
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                [updaterDelegate updater:self.updater willInstallUpdateOnQuit:self.updateItem immediateInstallationInvocation:invocation];
#pragma clang diagnostic pop
                
                // We have to assume they will handle the installation since they implement this method
                // Not ideal, but this is why this delegate callback is deprecated
                installationHandledByDelegate = YES;
            }
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
    [self.userDriver terminateApplication];
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
    BOOL showNextUpdateImmediately = (error == nil || error.code == SUInstallationAuthorizeLaterError) && (!self.willInstallSilently || self.updateItem.isCriticalUpdate);
    [self.coreDriver abortUpdateAndShowNextUpdateImmediately:showNextUpdateImmediately error:error];
}

@end
