//
//  SUUserInitiatedUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUserInitiatedUpdateDriver.h"
#import "SUUIBasedUpdateDriver.h"
#import "SUUserDriver.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUUserInitiatedUpdateDriver () <SUUIBasedUpdateDriverDelegate>

@property (nonatomic, readonly) SUUIBasedUpdateDriver *uiDriver;
@property (nonatomic, readonly) id<SUUserDriver> userDriver;
@property (nonatomic) BOOL showingUserInitiatedProgress;

@end

@implementation SUUserInitiatedUpdateDriver

@synthesize uiDriver = _uiDriver;
@synthesize userDriver = _userDriver;
@synthesize showingUserInitiatedProgress = _showingUserInitiatedProgress;

- (instancetype)initWithHost:(SUHost *)host sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater userDriver:(id <SUUserDriver>)userDriver updaterDelegate:(nullable id <SUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _uiDriver = [[SUUIBasedUpdateDriver alloc] initWithHost:host sparkleBundle:sparkleBundle updater:updater userDriver:userDriver updaterDelegate:updaterDelegate delegate:self];
        _userDriver = userDriver;
    }
    return self;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders completion:(SUUpdateDriverCompletion)completionBlock
{
    self.showingUserInitiatedProgress = YES;
    
    [self.userDriver showUserInitiatedUpdateCheckWithCompletion:^(SUUserInitiatedCheckStatus completionStatus) {
        switch (completionStatus) {
            case SUUserInitiatedCheckDone:
                break;
            case SUUserInitiatedCheckCanceled:
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.showingUserInitiatedProgress) {
                        [self abortUpdate];
                    }
                });
                break;
        }
    }];
    
    [self.uiDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders includesSkippedUpdates:YES completion:completionBlock];
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
    [self.uiDriver abortUpdateWithError:error];
}

@end
