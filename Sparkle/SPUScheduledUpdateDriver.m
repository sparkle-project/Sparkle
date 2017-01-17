//
//  SPUScheduledUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUScheduledUpdateDriver.h"
#import "SUHost.h"
#import "SUErrors.h"
#import "SPUUpdaterDelegate.h"
#import "SPUUserDriver.h"


#include "AppKitPrevention.h"

@interface SPUScheduledUpdateDriver() <SPUUIBasedUpdateDriverDelegate>

@property (nonatomic, readonly) SPUUIBasedUpdateDriver *uiDriver;

@end

@implementation SPUScheduledUpdateDriver

@synthesize uiDriver = _uiDriver;

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _uiDriver = [[SPUUIBasedUpdateDriver alloc] initWithHost:host applicationBundle:applicationBundle sparkleBundle:sparkleBundle updater:updater userDriver:userDriver userInitiated:NO updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders preventingInstallerInteraction:(BOOL)preventsInstallerInteraction completion:(SPUUpdateDriverCompletion)completionBlock
{
    [self.uiDriver prepareCheckForUpdatesWithCompletion:completionBlock];
    
    [self.uiDriver preflightForUpdatePermissionPreventingInstallerInteraction:preventsInstallerInteraction reply:^(NSError * _Nullable error) {
        if (error != nil) {
            // Don't tell the user about the permission error for scheduled update checks
            [self abortUpdateWithError:nil];
        } else {
            [self.uiDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders inBackground:YES includesSkippedUpdates:YES];
        }
    }];
}

- (void)resumeInstallingUpdateWithCompletion:(SPUUpdateDriverCompletion)completionBlock
{
    [self.uiDriver resumeInstallingUpdateWithCompletion:completionBlock];
}

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate completion:(SPUUpdateDriverCompletion)completionBlock
{
    [self.uiDriver resumeUpdate:resumableUpdate completion:completionBlock];
}

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)__unused error
{
    // Don't tell the user that no update was found or some appcast fetch error occurred for scheduled update checks
    [self abortUpdateWithError:nil];
}

- (void)coreDriverIsRequestingAbortUpdateWithError:(nullable NSError *)__unused error
{
    // Don't tell the user that a non-UI update error occurred for scheduled update checks
    [self abortUpdateWithError:nil];
}

- (void)uiDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)abortUpdate
{
    [self abortUpdateWithError:nil];
}

- (void)abortUpdateWithError:(nullable NSError *)error
{
    [self.uiDriver abortUpdateWithError:error];
}

@end
