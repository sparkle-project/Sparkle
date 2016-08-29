//
//  SUUserInitiatedUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUserInitiatedUpdateDriver.h"
#import "SUUIBasedUpdateDriver.h"
#import "SPUUserDriver.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUUserInitiatedUpdateDriver () <SUUIBasedUpdateDriverDelegate>

@property (nonatomic, readonly) SUUIBasedUpdateDriver *uiDriver;
@property (nonatomic, readonly) id<SPUUserDriver> userDriver;
@property (nonatomic) BOOL showingUserInitiatedProgress;
@property (nonatomic) BOOL aborted;

@end

@implementation SUUserInitiatedUpdateDriver

@synthesize uiDriver = _uiDriver;
@synthesize userDriver = _userDriver;
@synthesize showingUserInitiatedProgress = _showingUserInitiatedProgress;
@synthesize aborted = _aborted;

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _uiDriver = [[SUUIBasedUpdateDriver alloc] initWithHost:host applicationBundle:applicationBundle sparkleBundle:sparkleBundle updater:updater userDriver:userDriver userInitiated:YES updaterDelegate:updaterDelegate delegate:self];
        _userDriver = userDriver;
    }
    return self;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders preventingInstallerInteraction:(BOOL)preventsInstallerInteraction completion:(SUUpdateDriverCompletion)completionBlock
{
    [self.uiDriver prepareCheckForUpdatesWithCompletion:completionBlock];
    
    [self.uiDriver preflightForUpdatePermissionPreventingInstallerInteraction:preventsInstallerInteraction reply:^(NSError * _Nullable error) {
        if (!self.aborted) {
            if (error != nil) {
                [self abortUpdateWithError:error];
            } else {
                self.showingUserInitiatedProgress = YES;
                
                [self.userDriver showUserInitiatedUpdateCheckWithCompletion:^(SPUUserInitiatedCheckStatus completionStatus) {
                    switch (completionStatus) {
                        case SPUUserInitiatedCheckDone:
                            break;
                        case SPUUserInitiatedCheckCanceled:
                            dispatch_async(dispatch_get_main_queue(), ^{
                                if (self.showingUserInitiatedProgress) {
                                    [self abortUpdate];
                                }
                            });
                            break;
                    }
                }];
                
                [self.uiDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders includesSkippedUpdates:YES];
            }
        }
    }];
}

- (void)resumeInstallingUpdateWithCompletion:(SUUpdateDriverCompletion)completionBlock
{
    [self.uiDriver resumeInstallingUpdateWithCompletion:completionBlock];
}

- (void)resumeDownloadedUpdate:(SUDownloadedUpdate *)downloadedUpdate completion:(SUUpdateDriverCompletion)completionBlock
{
    [self.uiDriver resumeDownloadedUpdate:downloadedUpdate completion:completionBlock];
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
        [self.userDriver dismissUserInitiatedUpdateCheck];
    }
}

- (void)abortUpdate
{
    [self abortUpdateWithError:nil];
}

- (void)abortUpdateWithError:(nullable NSError *)error
{
    if (self.showingUserInitiatedProgress) {
        [self.userDriver dismissUserInitiatedUpdateCheck];
        self.showingUserInitiatedProgress = NO;
    }
    self.aborted = YES;
    [self.uiDriver abortUpdateWithError:error];
}

@end
