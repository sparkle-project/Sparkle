//
//  SUProbingUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUProbingUpdateDriver.h"
#import "SUBasicUpdateDriver.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUProbingUpdateDriver () <SUBasicUpdateDriverDelegate>

@property (nonatomic, readonly) SUBasicUpdateDriver *basicDriver;

@end

@implementation SUProbingUpdateDriver

@synthesize basicDriver = _basicDriver;

- (instancetype)initWithHost:(SUHost *)host updater:(id)updater updaterDelegate:(id <SUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _basicDriver = [[SUBasicUpdateDriver alloc] initWithHost:host updater:updater updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders completion:(SUUpdateDriverCompletion)completionBlock
{
    [self.basicDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders includesSkippedUpdates:NO completion:completionBlock];
}

- (BOOL)basicDriverShouldSignalShowingUpdateImmediately
{
    return NO;
}

- (void)resumeUpdateWithCompletion:(SUUpdateDriverCompletion)completionBlock
{
    [self.basicDriver resumeUpdateWithCompletion:completionBlock];
}

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)__unused appcastItem
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
    [self.basicDriver abortUpdateWithError:error];
}

@end
