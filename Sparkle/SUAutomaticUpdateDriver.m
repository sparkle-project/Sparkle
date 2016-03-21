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

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUAutomaticUpdateDriver () <SUCoreBasedUpdateDriverDelegate>

@property (nonatomic, readonly) SUCoreBasedUpdateDriver *coreDriver;
@property (nonatomic) BOOL foundCriticalUpdate;

@end

@implementation SUAutomaticUpdateDriver

@synthesize coreDriver = _coreDriver;
@synthesize foundCriticalUpdate = _foundCriticalUpdate;

- (instancetype)initWithHost:(SUHost *)host sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater updaterDelegate:(nullable id <SUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _coreDriver = [[SUCoreBasedUpdateDriver alloc] initWithHost:host sparkleBundle:sparkleBundle updater:updater updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders completion:(SUUpdateDriverCompletion)completionBlock
{
    [self.coreDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders includesSkippedUpdates:NO completion:completionBlock];
}

- (void)resumeUpdateWithCompletion:(SUUpdateDriverCompletion)__unused completionBlock __attribute__((noreturn))
{
    // Nothing really to do here.. this shouldn't be called.
    SULog(@"Error: resumeUpdateWithCompletion: called on SUAutomaticUpdateDriver");
    assert(false);
}

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)updateItem
{
    self.foundCriticalUpdate = [updateItem isCriticalUpdate];
    
    [self.coreDriver downloadUpdateFromAppcastItem:updateItem];
}

- (void)installerDidFinishRelaunchPreparation
{
    // We are done and can safely abort now
    // The installer tool will keep the installation alive
    [self abortUpdate];
}

- (BOOL)basicDriverShouldSignalShowingUpdateImmediately
{
    return self.foundCriticalUpdate;
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
    [self.coreDriver abortUpdateWithError:error];
}

@end
