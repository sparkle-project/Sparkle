//
//  SPUUpdaterTimer.m
//  Sparkle
//
//  Created by Mayur Pawashe on 8/12/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUpdaterTimer.h"


#include "AppKitPrevention.h"

@interface SPUUpdaterTimer ()

@property (nonatomic, readonly, weak) id<SPUUpdaterTimerDelegate> delegate;
@property (nonatomic, nullable) NSTimer *timer;

@end

@implementation SPUUpdaterTimer

@synthesize delegate = _delegate;
@synthesize timer = _timer;

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
    assert(self.timer == nil);
    self.timer = [NSTimer scheduledTimerWithTimeInterval:delay target:self selector:@selector(fire:) userInfo:nil repeats:NO];
}

- (void)fire:(NSTimer *)__unused timer
{
    [self.delegate updaterTimerDidFire];
    self.timer = nil;
}

- (void)invalidate
{
    [self.timer invalidate];
    self.timer = nil;
}

@end
