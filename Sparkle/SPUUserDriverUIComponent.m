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
    [self terminateApplicationForBundleAndWillTerminateCurrentApplication:bundle];
}

- (BOOL)terminateApplicationForBundleAndWillTerminateCurrentApplication:(NSBundle *)bundle
{
    NSRunningApplication *currentRunningApplication = [NSRunningApplication currentApplication];
    BOOL willTerminateSelf = NO;
    
    NSArray<NSRunningApplication *> *runningApplications = [SPUApplicationInfo runningApplicationsWithBundle:bundle];
    for (NSRunningApplication *runningApplication in runningApplications) {
        if (!willTerminateSelf && [currentRunningApplication isEqual:runningApplication]) {
            willTerminateSelf = YES;
        }
        [runningApplication terminate];
    }
    
    return willTerminateSelf;
}

- (BOOL)applicationIsAliveForBundle:(NSBundle *)bundle
{
    return ([SPUApplicationInfo runningApplicationWithBundle:bundle] != nil);
}

@end
