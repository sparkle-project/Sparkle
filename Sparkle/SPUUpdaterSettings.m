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

@interface SPUUpdaterSettings ()

@property (nonatomic, readonly) SUHost *host;

@end

@implementation SPUUpdaterSettings

@synthesize host = _host;

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
    return [self.host boolForKey:SUEnableAutomaticChecksKey];
}

- (NSTimeInterval)updateCheckInterval
{
    // Find the stored check interval. User defaults override Info.plist.
    NSNumber *intervalValue = [self.host objectForKey:SUScheduledCheckIntervalKey];
    if (intervalValue)
        return [intervalValue doubleValue];
    else
        return SUDefaultUpdateCheckInterval;
}

// For allowing automatic downloaded updates to be turned on or off
- (BOOL)allowsAutomaticUpdates
{
    NSNumber *developerAllowsAutomaticUpdates = [self.host objectForInfoDictionaryKey:SUAllowsAutomaticUpdatesKey];
    return (developerAllowsAutomaticUpdates == nil || developerAllowsAutomaticUpdates.boolValue);
}

- (BOOL)automaticallyDownloadsUpdates
{
    return [self.host boolForKey:SUAutomaticallyUpdateKey];
}

- (BOOL)sendsSystemProfile
{
    return [self.host boolForKey:SUSendProfileInfoKey];
}

@end
