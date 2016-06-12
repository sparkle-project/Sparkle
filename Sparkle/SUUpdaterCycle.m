//
//  SUUpdaterCycle.m
//  Sparkle
//
//  Created by Mayur Pawashe on 6/11/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUpdaterCycle.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUUpdaterCycle ()

@property (nonatomic, weak, readonly) id<SUUpdaterCycleDelegate> delegate;

@end

@implementation SUUpdaterCycle

@synthesize delegate = _delegate;

- (instancetype)initWithDelegate:(id<SUUpdaterCycleDelegate>)delegate
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
