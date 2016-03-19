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
@property (nonatomic) BOOL canceledCheckForUpdates;

@end

@implementation SUUserInitiatedUpdateDriver

@synthesize uiDriver = _uiDriver;
@synthesize canceledCheckForUpdates = _canceledCheckForUpdates;

- (instancetype)initWithHost:(SUHost *)host sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater userDriver:(id <SUUserDriver>)userDriver updaterDelegate:(nullable id <SUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _uiDriver = [[SUUIBasedUpdateDriver alloc] initWithHost:host sparkleBundle:sparkleBundle updater:updater userDriver:userDriver updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders completion:(void (^)(void))completionBlock
{
    [self.uiDriver.userDriver showUserInitiatedUpdateCheckWithCompletion:^(SUUserInitiatedCheckStatus completionStatus) {
        switch (completionStatus) {
            case SUUserInitiatedCheckDone:
                break;
            case SUUserInitiatedCheckCancelled:
                dispatch_async(dispatch_get_main_queue(), ^{
                    self.canceledCheckForUpdates = YES;
                    [self.uiDriver.userDriver dismissUserInitiatedUpdateCheck];
                });
                break;
        }
    }];
    
    [self.uiDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders includesSkippedUpdates:YES completion:completionBlock];
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
    if (self.canceledCheckForUpdates) {
        [self abortUpdate];
    }
}

- (void)abortUpdate
{
    [self abortUpdateWithError:nil];
}

- (void)abortUpdateWithError:(nullable NSError *)error
{
    [self.uiDriver.userDriver dismissUserInitiatedUpdateCheck];
    [self.uiDriver abortUpdateWithError:error];
}

@end
