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
@property (nonatomic) dispatch_source_t source;
@property (nonatomic) dispatch_source_t cooldownSource;

@end

@implementation SPUUpdaterTimer

@synthesize delegate = _delegate;
@synthesize source = _source;
@synthesize cooldownSource = _cooldownSource;

- (instancetype)initWithDelegate:(id<SPUUpdaterTimerDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

- (void)startAndFireAfterDelay:(NSTimeInterval)delay
{
    __block BOOL timerFired = NO;
    __block BOOL cooldownFired = NO;
    
    // We use the wall time instead of cpu time for our dispatch timer
    // So eg if the computer sleeps we want to include that time spent in our timer
    self.source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    
    dispatch_time_t timeToFire = dispatch_walltime(NULL, (int64_t)(delay * NSEC_PER_SEC));
    dispatch_source_set_timer(self.source, timeToFire, DISPATCH_TIME_FOREVER, SULeewayUpdateCheckInterval * NSEC_PER_SEC);
    
    __weak __typeof__(self) weakSelf = self;
    dispatch_source_set_event_handler(self.source, ^{
        timerFired = YES;
        
        if (cooldownFired) {
            [weakSelf.delegate updaterTimerDidFire];
        }
    });
    
    // However we also keep a cooldown timer that is monotonic
    // This ensures we don't fire too frequently if the real clock changes
    self.cooldownSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    
    dispatch_time_t cooldownTimeToFire = dispatch_time(DISPATCH_TIME_NOW , 45 * NSEC_PER_SEC);
    dispatch_source_set_timer(self.cooldownSource, cooldownTimeToFire, DISPATCH_TIME_FOREVER, SULeewayUpdateCheckInterval * NSEC_PER_SEC);
    
    dispatch_source_set_event_handler(self.cooldownSource, ^{
        cooldownFired = YES;
        
        if (timerFired) {
            [weakSelf.delegate updaterTimerDidFire];
        }
    });
    
    // Resume timers
    dispatch_resume(self.source);
    dispatch_resume(self.cooldownSource);
}

- (void)invalidate
{
    if (self.source != nil) {
        dispatch_source_cancel(self.source);
        self.source = nil;
    }
    
    if (self.cooldownSource != nil) {
        dispatch_source_cancel(self.cooldownSource);
        self.cooldownSource = nil;
    }
}

@end
