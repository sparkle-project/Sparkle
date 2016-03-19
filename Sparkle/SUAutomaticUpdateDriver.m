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

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUAutomaticUpdateDriver () <SUCoreBasedUpdateDriverDelegate>

@property (nonatomic, readonly) SUCoreBasedUpdateDriver *coreDriver;

@end

@implementation SUAutomaticUpdateDriver

@synthesize coreDriver = _coreDriver;

- (instancetype)initWithHost:(SUHost *)host sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater updaterDelegate:(nullable id <SUUpdaterDelegate>)updaterDelegate
{
    self = [super init];
    if (self != nil) {
        _coreDriver = [[SUCoreBasedUpdateDriver alloc] initWithHost:host sparkleBundle:sparkleBundle updater:updater updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders completion:(void (^)(void))completionBlock
{
    [self.coreDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders includesSkippedUpdates:NO completion:completionBlock];
}

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)updateItem
{
    [self.coreDriver downloadUpdateFromAppcastItem:updateItem];
}

- (void)installerDidFinishRelaunchPreparation
{
    // We are done and can safely abort now
    // The installer tool will keep the installation alive
    [self abortUpdate];
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
