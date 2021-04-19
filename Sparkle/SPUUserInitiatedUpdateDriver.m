//
//  SPUUserInitiatedUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUserInitiatedUpdateDriver.h"
#import "SPUUIBasedUpdateDriver.h"
#import "SPUUserDriver.h"


#include "AppKitPrevention.h"

@interface SPUUserInitiatedUpdateDriver () <SPUUIBasedUpdateDriverDelegate>

@property (nonatomic, readonly) SPUUIBasedUpdateDriver *uiDriver;
@property (nonatomic, readonly) id<SPUUserDriver> userDriver;
@property (nonatomic) BOOL showingUserInitiatedProgress;
@property (nonatomic) BOOL showingUpdate;
@property (nonatomic) BOOL aborted;

@end

@implementation SPUUserInitiatedUpdateDriver

@synthesize uiDriver = _uiDriver;
@synthesize userDriver = _userDriver;
@synthesize showingUserInitiatedProgress = _showingUserInitiatedProgress;
@synthesize showingUpdate = _showingUpdate;
@synthesize aborted = _aborted;

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _uiDriver = [[SPUUIBasedUpdateDriver alloc] initWithHost:host applicationBundle:applicationBundle sparkleBundle:sparkleBundle updater:updater userDriver:userDriver userInitiated:YES updaterDelegate:updaterDelegate delegate:self];
        _userDriver = userDriver;
    }
    return self;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders preventingInstallerInteraction:(BOOL)preventsInstallerInteraction completion:(SPUUpdateDriverCompletion)completionBlock
{
    [self.uiDriver prepareCheckForUpdatesWithCompletion:completionBlock];
    
    [self.uiDriver preflightForUpdatePermissionPreventingInstallerInteraction:preventsInstallerInteraction reply:^(NSError * _Nullable error) {
        if (!self.aborted) {
            if (error != nil) {
                [self abortUpdateWithError:error];
            } else {
                self.showingUserInitiatedProgress = YES;
                
                void (^cancelUpdateCheck)(void) = ^{
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (self.showingUserInitiatedProgress) {
                            [self abortUpdate];
                        }
                    });
                };
                
                self.showingUpdate = YES;
                
                if ([self.userDriver respondsToSelector:@selector(showUserInitiatedUpdateCheckWithCancellation:)]) {
                    [self.userDriver showUserInitiatedUpdateCheckWithCancellation:cancelUpdateCheck];
                } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                    [self.userDriver showUserInitiatedUpdateCheckWithCompletion:^(SPUUserInitiatedCheckStatus completionStatus) {
#pragma clang diagnostic pop
                        switch (completionStatus) {
                            case SPUUserInitiatedCheckDone:
                                break;
                            case SPUUserInitiatedCheckCanceled:
                                cancelUpdateCheck();
                                break;
                        }
                    }];
                }
                
                [self.uiDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders inBackground:NO includesSkippedUpdates:YES];
            }
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

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)coreDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)uiDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)basicDriverDidFinishLoadingAppcast
{
    if (self.showingUserInitiatedProgress) {
        self.showingUserInitiatedProgress = NO;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if ([self.userDriver respondsToSelector:@selector(dismissUserInitiatedUpdateCheck)]) {
            [self.userDriver dismissUserInitiatedUpdateCheck];
        }
#pragma clang diagnostic pop
    }
}

- (void)abortUpdate
{
    [self abortUpdateWithError:nil];
}

- (void)abortUpdateWithError:(nullable NSError *)error
{
    if (self.showingUserInitiatedProgress) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if ([self.userDriver respondsToSelector:@selector(dismissUserInitiatedUpdateCheck)]) {
            [self.userDriver dismissUserInitiatedUpdateCheck];
        }
#pragma clang diagnostic pop
        self.showingUserInitiatedProgress = NO;
    }
    self.aborted = YES;
    [self.uiDriver abortUpdateWithError:error];
}

@end
