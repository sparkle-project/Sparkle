//
//  SUScheduledUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUScheduledUpdateDriver.h"
#import "SUHost.h"
#import "SUErrors.h"
#import "SUUpdaterDelegate.h"
#import "SPUUserDriver.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUScheduledUpdateDriver() <SUUIBasedUpdateDriverDelegate>

@property (nonatomic, readonly) SUUIBasedUpdateDriver *uiDriver;

@end

@implementation SUScheduledUpdateDriver

@synthesize uiDriver = _uiDriver;

- (instancetype)initWithHost:(SUHost *)host sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver updaterDelegate:(nullable id <SUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _uiDriver = [[SUUIBasedUpdateDriver alloc] initWithHost:host sparkleBundle:sparkleBundle updater:updater userDriver:userDriver updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders completion:(SUUpdateDriverCompletion)completionBlock
{
    [self.uiDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders includesSkippedUpdates:NO completion:completionBlock];
}

- (void)resumeInstallingUpdateWithCompletion:(SUUpdateDriverCompletion)completionBlock
{
    [self.uiDriver resumeInstallingUpdateWithCompletion:completionBlock];
}

- (void)resumeDownloadedUpdate:(SUDownloadedUpdate *)downloadedUpdate completion:(SUUpdateDriverCompletion)completionBlock
{
    [self.uiDriver resumeDownloadedUpdate:downloadedUpdate completion:completionBlock];
}

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)__unused error
{
    // Don't tell the user that no update was found or some appcast fetch error occurred for scheduled update checks
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
