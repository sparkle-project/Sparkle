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

@interface TerminationListener ()

@property (nonatomic, strong) NSNumber *processIdentifier;
@property (nonatomic, strong) NSTimer *watchdogTimer;

@end

@implementation TerminationListener

@synthesize processIdentifier = _processIdentifier;
@synthesize watchdogTimer = _watchdogTimer;

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
    
    completionBlock(success);
}

- (void)startListeningWithCompletion:(void (^)(BOOL))completionBlock
{
    BOOL alreadyTerminated = (self.processIdentifier == nil || (kill(self.processIdentifier.intValue, 0) != 0));
    if (alreadyTerminated) {
        [self cleanupWithSuccess:YES completion:completionBlock];
    } else {
        self.watchdogTimer = [NSTimer scheduledTimerWithTimeInterval:SUParentQuitCheckInterval target:self selector:@selector(watchdog:) userInfo:completionBlock repeats:YES];
    }
}

- (void)watchdog:(NSTimer *)timer
{
    if ([NSRunningApplication runningApplicationWithProcessIdentifier:self.processIdentifier.intValue] == nil) {
        [self cleanupWithSuccess:YES completion:timer.userInfo];
    }
}

@end
