//
//  SPUUpdaterSettings.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/27/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUpdaterSettings.h"
#import "SUHost.h"
#import "SUConstants.h"


#include "AppKitPrevention.h"

@implementation SPUUpdaterSettings
{
    SUHost *_host;
}

- (instancetype)initWithHostBundle:(NSBundle *)hostBundle
{
    self = [super init];
    if (self != nil) {
        _host = [[SUHost alloc] initWithBundle:hostBundle];
    }
    return self;
}

- (BOOL)automaticallyChecksForUpdates
{
    // Don't automatically update when the check interval is 0, to be compatible with 1.1 settings.
    if ((NSInteger)[self updateCheckInterval] == 0) {
        return NO;
    }
    return [_host boolForKey:SUEnableAutomaticChecksKey];
}

- (NSTimeInterval)updateCheckInterval
{
    // Find the stored check interval. User defaults override Info.plist.
    NSNumber *intervalValue = [_host objectForKey:SUScheduledCheckIntervalKey];
    if (intervalValue)
        return [intervalValue doubleValue];
    else
        return SUDefaultUpdateCheckInterval;
}

// For allowing automatic downloaded updates to be turned on or off
- (NSNumber * _Nullable)allowsAutomaticUpdatesOption
{
    NSNumber *developerAllowsAutomaticUpdates = [_host objectForInfoDictionaryKey:SUAllowsAutomaticUpdatesKey];
    return [developerAllowsAutomaticUpdates isKindOfClass:[NSNumber class]] ? developerAllowsAutomaticUpdates : nil;
}

- (BOOL)allowsAutomaticUpdates
{
    NSNumber *developerAllowsAutomaticUpdates = [self allowsAutomaticUpdatesOption];
    return (developerAllowsAutomaticUpdates == nil || developerAllowsAutomaticUpdates.boolValue);
}

- (BOOL)automaticallyDownloadsUpdates
{
    return [_host boolForKey:SUAutomaticallyUpdateKey];
}

- (BOOL)sendsSystemProfile
{
    return [_host boolForKey:SUSendProfileInfoKey];
}

@end
