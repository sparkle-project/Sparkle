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

@end

@implementation SPUUpdaterTimer

@synthesize delegate = _delegate;
@synthesize source = _source;

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
    self.source = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    
    // We use the wall time instead of cpu time for our dispatch timer
    // So eg if the computer sleeps we want to include that time spent in our timer
    dispatch_time_t timeToFire = dispatch_walltime(NULL, (int64_t)(delay * NSEC_PER_SEC));
    dispatch_source_set_timer(self.source, timeToFire, DISPATCH_TIME_FOREVER, SULeewayUpdateCheckInterval * NSEC_PER_SEC);
    
    __weak __typeof__(self) weakSelf = self;
    dispatch_source_set_event_handler(self.source, ^{
        [weakSelf.delegate updaterTimerDidFire];
    });
    
    dispatch_resume(self.source);
}

- (void)invalidate
{
    if (self.source != nil) {
        dispatch_source_cancel(self.source);
        self.source = nil;
    }
}

@end
