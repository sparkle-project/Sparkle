//
//  TerminationListener.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/7/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "TerminationListener.h"

/*!
 * Time this app uses to recheck if the host app has already died.
 */
static const NSTimeInterval SUParentQuitCheckInterval = .25;

/*!
 * Timeout to wait until the host app has died.
 */
static const NSTimeInterval SUParentQuitTimeoutInterval = 30.0;

@interface TerminationListener ()

@property (nonatomic, strong) NSNumber *processIdentifier;
@property (nonatomic, strong) NSTimer *watchdogTimer;
@property (nonatomic, strong) NSTimer *timeoutTimer;

@end

@implementation TerminationListener

@synthesize processIdentifier = _processIdentifier;
@synthesize watchdogTimer = _watchdogTimer;
@synthesize timeoutTimer = _timeoutTimer;

- (instancetype)initWithProcessIdentifier:(NSNumber *)processIdentifier
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self.processIdentifier = processIdentifier;
    
    return self;
}

- (void)cleanupWithSuccess:(BOOL)success completion:(void (^)(BOOL))completionBlock
{
    [self.watchdogTimer invalidate];
    [self.timeoutTimer invalidate];
    
    completionBlock(success);
}

- (void)startListeningWithCompletion:(void (^)(BOOL))completionBlock
{
    BOOL alreadyTerminated = (self.processIdentifier == nil || (kill(self.processIdentifier.intValue, 0) != 0));
    if (alreadyTerminated) {
        [self cleanupWithSuccess:YES completion:completionBlock];
    } else {
        self.watchdogTimer = [NSTimer scheduledTimerWithTimeInterval:SUParentQuitCheckInterval target:self selector:@selector(watchdog:) userInfo:completionBlock repeats:YES];
        
        self.timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:SUParentQuitTimeoutInterval target:self selector:@selector(timeout:) userInfo:completionBlock repeats:NO];
    }
}

- (void)watchdog:(NSTimer *)timer
{
    if ([NSRunningApplication runningApplicationWithProcessIdentifier:self.processIdentifier.intValue] == nil) {
        [self cleanupWithSuccess:YES completion:timer.userInfo];
    }
}

- (void)timeout:(NSTimer *)timer
{
    if (self.watchdogTimer.valid) {
        [self cleanupWithSuccess:NO completion:timer.userInfo];
    }
}

@end
