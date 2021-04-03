//
//  SPUProbingUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUProbingUpdateDriver.h"
#import "SPUBasicUpdateDriver.h"


#include "AppKitPrevention.h"

@interface SPUProbingUpdateDriver () <SPUBasicUpdateDriverDelegate>

@property (nonatomic, readonly) SPUBasicUpdateDriver *basicDriver;
@property (nonatomic) id<SPUResumableUpdate> resumableUpdate;

@end

@implementation SPUProbingUpdateDriver

@synthesize basicDriver = _basicDriver;
@synthesize resumableUpdate = _resumableUpdate;

- (instancetype)initWithHost:(SUHost *)host updater:(id)updater updaterDelegate:(id <SPUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _basicDriver = [[SPUBasicUpdateDriver alloc] initWithHost:host updater:updater updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders preventingInstallerInteraction:(BOOL)__unused preventsInstallerInteraction completion:(SPUUpdateDriverCompletion)completionBlock
{
    // We don't preflight for update permission in this driver because we are just interested if an update is available
    
    [self.basicDriver prepareCheckForUpdatesWithCompletion:completionBlock];
    
    [self.basicDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders inBackground:YES includesSkippedUpdates:NO];
}

- (void)resumeInstallingUpdateWithCompletion:(SPUUpdateDriverCompletion)completionBlock
{
    [self.basicDriver resumeInstallingUpdateWithCompletion:completionBlock];
}

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate completion:(SPUUpdateDriverCompletion)completionBlock
{
    self.resumableUpdate = resumableUpdate;
    
    [self.basicDriver resumeUpdate:resumableUpdate completion:completionBlock];
}

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)__unused appcastItem preventsAutoupdate:(BOOL)__unused preventsAutoupdate systemDomain:(NSNumber * _Nullable)__unused systemDomain
{
    // Stop as soon as we have an answer
    [self abortUpdate];
}

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)abortUpdate
{
    [self abortUpdateWithError:nil];
}

- (void)abortUpdateWithError:(nullable NSError *)error
{
    [self.basicDriver abortUpdateAndShowNextUpdateImmediately:NO resumableUpdate:self.resumableUpdate error:error];
}

@end
