//
//  TestAppHelper.m
//  TestAppHelper
//
//  Created by Mayur Pawashe on 3/2/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "TestAppHelper.h"
#import "SUAdHocCodeSigning.h"
#import <Sparkle/Sparkle.h>

@interface TestAppHelper ()

@property (nonatomic) SPUUpdater *updater;
@property (nonatomic) id <SPUUserDriver> userDriver;

@end

@implementation TestAppHelper

@synthesize updater = _updater;
@synthesize userDriver = _userDriver;

- (instancetype)initWithUserDriver:(id <SPUUserDriver>)userDriver
{
    self = [super init];
    if (self != nil) {
        _userDriver = userDriver;
    }
    return self;
}

- (void)codeSignApplicationAtPath:(NSString *)applicationPath reply:(void (^)(BOOL))reply
{
    reply([SUAdHocCodeSigning codeSignApplicationAtPath:applicationPath]);
}

- (void)startSparkleIfNeeded
{
    if (self.updater == nil) {
        NSURL *appURL = [[[[[NSBundle mainBundle] bundleURL] URLByDeletingLastPathComponent] URLByDeletingLastPathComponent] URLByDeletingLastPathComponent];
        
        NSBundle *hostBundle = [NSBundle bundleWithURL:appURL];
        self.updater = [[SPUUpdater alloc] initWithHostBundle:hostBundle userDriver:self.userDriver delegate:nil];
        
        NSError *updaterError = nil;
        if (![self.updater startUpdater:&updaterError]) {
            NSLog(@"Encountered error while starting updater in Test App Helper: %@", updaterError);
            abort();
        }
    }
}

- (void)startSparkle
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self startSparkleIfNeeded];
    });
}

- (void)initiateUserCheckForUpdates
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self startSparkleIfNeeded];
        [self.updater checkForUpdates];
    });
}

- (void)checkForUpdates
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self startSparkleIfNeeded];
        [self.updater resetUpdateCycle];
    });
}

- (void)setAutomaticallyChecksForUpdates:(BOOL)automaticallyChecksForUpdates
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self startSparkleIfNeeded];
        self.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates;
    });
}

- (void)setAutomaticallyDownloadsUpdates:(BOOL)automaticallyDownloadsUpdates
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self startSparkleIfNeeded];
        self.updater.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates;
    });
}

- (void)setSendsSystemProfile:(BOOL)sendsSystemProfile
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self startSparkleIfNeeded];
        self.updater.sendsSystemProfile = sendsSystemProfile;
    });
}

- (void)setUpdateCheckInterval:(NSTimeInterval)updateCheckInterval
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self startSparkleIfNeeded];
        self.updater.updateCheckInterval = updateCheckInterval;
    });
}

@end
