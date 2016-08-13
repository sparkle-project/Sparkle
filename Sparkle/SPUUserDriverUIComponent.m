//
//  SPUUserDriverUIComponent.m
//  Sparkle
//
//  Created by Mayur Pawashe on 8/13/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUserDriverUIComponent.h"
#import "SPUApplicationInfo.h"

@implementation SPUUserDriverUIComponent

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
    }
    return self;
}

- (void)terminateApplicationForBundle:(NSBundle *)bundle
{
    NSRunningApplication *runningApplication = [SPUApplicationInfo runningApplicationWithBundle:bundle];
    if (runningApplication != nil) {
        [runningApplication terminate];
    }
}

@end
