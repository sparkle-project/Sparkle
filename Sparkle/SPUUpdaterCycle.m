//
//  SPUUpdaterCycle.m
//  Sparkle
//
//  Created by Mayur Pawashe on 6/11/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUpdaterCycle.h"


#include "AppKitPrevention.h"

@interface SPUUpdaterCycle ()

@property (nonatomic, weak, readonly) id<SPUUpdaterCycleDelegate> delegate;

@end

@implementation SPUUpdaterCycle

@synthesize delegate = _delegate;

- (instancetype)initWithDelegate:(id<SPUUpdaterCycleDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

- (void)resetUpdateCycle
{
    [self.delegate resetUpdateCycle];
}

- (void)resetUpdateCycleAfterDelay
{
    [self performSelector:@selector(resetUpdateCycle) withObject:nil afterDelay:1];
}

- (void)cancelNextUpdateCycle
{
    [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(resetUpdateCycle) object:nil];
}

@end
