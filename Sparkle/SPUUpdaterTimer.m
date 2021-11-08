//
//  SPUUpdaterTimer.m
//  Sparkle
//
//  Created by Mayur Pawashe on 8/12/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUpdaterTimer.h"
#import "SUConstants.h"


#include "AppKitPrevention.h"

@interface SPUUpdaterTimer ()

@property (nonatomic, readonly, weak) id<SPUUpdaterTimerDelegate> delegate;
@property (nonatomic) dispatch_source_t wallTimeSource;
@property (nonatomic) dispatch_source_t monotonicTimeSource;

@end

@implementation SPUUpdaterTimer

@synthesize delegate = _delegate;
@synthesize wallTimeSource = _wallTimeSource;
@synthesize monotonicTimeSource = _monotonicTimeSource;

- (instancetype)initWithDelegate:(id<SPUUpdaterTimerDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

- (void)startTimerWithWallTimeDelay:(NSTimeInterval)wallTimeDelay monotonicTimeDelay:(NSTimeInterval)monotonicTimeDelay
{
    __weak __typeof__(self) weakSelf = self;
    // When timersFired reaches 2, both wall/monotonic timers have been fired, and the delegate is ready to receive the notification
    __block uint8_t timersFired = 0;
    
    if (wallTimeDelay <= 0) {
        timersFired++;
        self.wallTimeSource = nil;
    } else {
        // We use the wall time instead of cpu time for a large date interval
        // So eg if the computer sleeps we want to include that time spent in our timer
        self.wallTimeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        
        dispatch_time_t wallTime = dispatch_walltime(NULL, (int64_t)(wallTimeDelay * NSEC_PER_SEC));
        dispatch_source_set_timer(self.wallTimeSource, wallTime, DISPATCH_TIME_FOREVER, SULeewayWallUpdateCheckInterval * NSEC_PER_SEC);
        
        dispatch_source_set_event_handler(self.wallTimeSource, ^{
            timersFired++;
            if (timersFired > 1) {
                [weakSelf.delegate updaterTimerDidFire];
            }
        });
    }
    
    if (monotonicTimeDelay <= 0) {
        timersFired++;
        self.monotonicTimeSource = nil;
    } else {
        // We also use monotonic time to enforce a minimum delay interval
        // This ensures we don't fire the wall clock based timer too frequently if the real clock changes
        self.monotonicTimeSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        
        dispatch_time_t monotonicTime = dispatch_time(DISPATCH_TIME_NOW , (int64_t)(monotonicTimeDelay * NSEC_PER_SEC));
        dispatch_source_set_timer(self.monotonicTimeSource, monotonicTime, DISPATCH_TIME_FOREVER, SULeewayMonotonicUpdateCheckInterval * NSEC_PER_SEC);
        
        dispatch_source_set_event_handler(self.monotonicTimeSource, ^{
            timersFired++;
            if (timersFired > 1) {
                [weakSelf.delegate updaterTimerDidFire];
            }
        });
    }
    
    // Have both timers already ran? (this should be unlikely)
    if (timersFired > 1) {
        [self.delegate updaterTimerDidFire];
    } else {
        // Resume available timers
        
        if (self.wallTimeSource != nil) {
            dispatch_resume(self.wallTimeSource);
        }
        
        if (self.monotonicTimeSource != nil) {
            dispatch_resume(self.monotonicTimeSource);
        }
    }
}

- (void)invalidate
{
    if (self.wallTimeSource != nil) {
        dispatch_source_cancel(self.wallTimeSource);
        self.wallTimeSource = nil;
    }
    
    if (self.monotonicTimeSource != nil) {
        dispatch_source_cancel(self.monotonicTimeSource);
        self.monotonicTimeSource = nil;
    }
}

@end
