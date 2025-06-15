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

static NSString *SUAutomaticallyChecksForUpdatesKeyPath = @"automaticallyChecksForUpdates";
static NSString *SUUpdateCheckIntervalKeyPath = @"updateCheckInterval";
static NSString *SUAutomaticallyDownloadsUpdatesKeyPath = @"automaticallyDownloadsUpdates";
static NSString *SUSendsSystemProfileKeyPath = @"sendsSystemProfile";

@implementation SPUUpdaterSettings
{
    SUHost *_host;
}

@synthesize automaticallyChecksForUpdates = _automaticallyChecksForUpdates;
@synthesize updateCheckInterval = _updateCheckInterval;
@synthesize automaticallyDownloadsUpdates = _automaticallyDownloadsUpdates;
@synthesize sendsSystemProfile = _sendsSystemProfile;

- (instancetype)initWithHostBundle:(NSBundle *)hostBundle
{
    self = [super init];
    if (self != nil) {
        _host = [[SUHost alloc] initWithBundle:hostBundle];
        
        _automaticallyChecksForUpdates = [self currentAutomaticallyChecksForUpdates];
        _updateCheckInterval = [self currentUpdateCheckInterval];
        _automaticallyDownloadsUpdates = [self currentAutomaticallyDownloadsUpdates];
        _sendsSystemProfile = [self currentSendsSystemProfile];
        
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(synchronize:) name:SUUpdateSettingsNeedsSynchronizationNotification object:nil];
        
        __weak __typeof__(self) weakSelf = self;
        [_host observeChangesFromUserDefaultKeys:[NSSet setWithArray:@[SUEnableAutomaticChecksKey, SUScheduledCheckIntervalKey, SUAutomaticallyUpdateKey, SUSendProfileInfoKey]] changeHandler:^(NSString *keyPath) {
            __typeof(self) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            
            if ([keyPath isEqualToString:SUEnableAutomaticChecksKey]) {
                [strongSelf processCurrentAutomaticallyChecksForUpdates];
            } else if ([keyPath isEqualToString:SUScheduledCheckIntervalKey]) {
                [strongSelf processUpdateCheckInterval];
            } else if ([keyPath isEqualToString:SUAutomaticallyUpdateKey]) {
                [strongSelf processAutomaticallyDownloadsUpdates];
            } else if ([keyPath isEqualToString:SUSendProfileInfoKey]) {
                [strongSelf processSendsSystemProfile];
            }
        }];
    }
    return self;
}

- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:self name:SUUpdateSettingsNeedsSynchronizationNotification object:_host.bundlePath];
}

- (void)processCurrentAutomaticallyChecksForUpdates SPU_OBJC_DIRECT
{
    BOOL currentValue = [self currentAutomaticallyChecksForUpdates];
    
    if (currentValue != _automaticallyChecksForUpdates) {
        NSString *updatedKeyPath = SUAutomaticallyChecksForUpdatesKeyPath;
        
        [self willChangeValueForKey:updatedKeyPath];
        
        _automaticallyChecksForUpdates = currentValue;
        
        [self didChangeValueForKey:updatedKeyPath];
    }
}

- (void)processUpdateCheckInterval SPU_OBJC_DIRECT
{
    NSTimeInterval currentValue = [self currentUpdateCheckInterval];
    
    if (fabs(currentValue - _updateCheckInterval) >= 0.001) {
        NSString *updatedKeyPath = SUUpdateCheckIntervalKeyPath;
        
        [self willChangeValueForKey:updatedKeyPath];
        
        _updateCheckInterval = currentValue;
        
        [self didChangeValueForKey:updatedKeyPath];
    }
}

- (void)processAutomaticallyDownloadsUpdates SPU_OBJC_DIRECT
{
    BOOL currentValue = [self currentAutomaticallyDownloadsUpdates];
    
    if (currentValue != _automaticallyDownloadsUpdates) {
        NSString *updatedKeyPath = SUAutomaticallyDownloadsUpdatesKeyPath;
        
        [self willChangeValueForKey:updatedKeyPath];
        
        _automaticallyDownloadsUpdates = currentValue;
        
        [self didChangeValueForKey:updatedKeyPath];
    }
}

- (void)processSendsSystemProfile SPU_OBJC_DIRECT
{
    BOOL currentValue = [self currentSendsSystemProfile];
    
    if (currentValue != _sendsSystemProfile) {
        NSString *updatedKeyPath = SUSendsSystemProfileKeyPath;
        
        [self willChangeValueForKey:updatedKeyPath];
        
        _sendsSystemProfile = currentValue;
        
        [self didChangeValueForKey:updatedKeyPath];
    }
}

- (void)synchronize:(NSNotification *)notification
{
    NSString *bundlePath = notification.userInfo[SUUpdateBundlePathUserInfoKey];
    if (![bundlePath isEqualToString:_host.bundlePath]) {
        return;
    }
    
    [self processCurrentAutomaticallyChecksForUpdates];
    [self processUpdateCheckInterval];
    [self processAutomaticallyDownloadsUpdates];
    [self processSendsSystemProfile];
}

- (BOOL)currentAutomaticallyChecksForUpdates SPU_OBJC_DIRECT
{
    // Don't automatically update when the check interval is 0, to be compatible with 1.1 settings.
    if ((NSInteger)[self currentUpdateCheckInterval] == 0) {
        return NO;
    }
    return [_host boolForKey:SUEnableAutomaticChecksKey];
}

- (void)setAutomaticallyChecksForUpdates:(BOOL)automaticallyCheckForUpdates
{
    [self willChangeValueForKey:SUAutomaticallyChecksForUpdatesKeyPath];
    
    _automaticallyChecksForUpdates = automaticallyCheckForUpdates;
    [_host setBool:automaticallyCheckForUpdates forUserDefaultsKey:SUEnableAutomaticChecksKey];
    
    [self didChangeValueForKey:SUAutomaticallyChecksForUpdatesKeyPath];
    
    // Hack to support backwards compatibility with older Sparkle versions, which supported
    // disabling updates by setting the check interval to 0.
    if (automaticallyCheckForUpdates && (NSInteger)[self currentUpdateCheckInterval] == 0) {
        [self setUpdateCheckInterval:SUDefaultUpdateCheckInterval];
    } else {
        [NSNotificationCenter.defaultCenter postNotificationName:SUUpdateAutomaticCheckSettingChangedNotification object:nil userInfo:@{SUUpdateBundlePathUserInfoKey: _host.bundlePath}];
    }
}

+ (BOOL)automaticallyNotifiesObserversOfAutomaticallyChecksForUpdates
{
    return NO;
}

- (NSTimeInterval)currentUpdateCheckInterval SPU_OBJC_DIRECT
{
    // Find the stored check interval. User defaults override Info.plist.
    id intervalValue = [_host objectForKey:SUScheduledCheckIntervalKey];
    if (intervalValue == nil || ![(NSObject *)intervalValue isKindOfClass:[NSNumber class]]) {
        return SUDefaultUpdateCheckInterval;
    }
    
    return [(NSNumber *)intervalValue doubleValue];
}

- (void)setUpdateCheckInterval:(NSTimeInterval)updateCheckInterval
{
    [self willChangeValueForKey:SUUpdateCheckIntervalKeyPath];
    
    _updateCheckInterval = updateCheckInterval;
    [_host setObject:@(updateCheckInterval) forUserDefaultsKey:SUScheduledCheckIntervalKey];
    
    [self didChangeValueForKey:SUUpdateCheckIntervalKeyPath];
    
    if ((NSInteger)updateCheckInterval == 0) { // For compatibility with 1.1's settings.
        [self setAutomaticallyChecksForUpdates:NO];
    } else {
        [NSNotificationCenter.defaultCenter postNotificationName:SUUpdateAutomaticCheckSettingChangedNotification object:nil userInfo:@{SUUpdateBundlePathUserInfoKey: _host.bundlePath}];
    }
}

+ (BOOL)automaticallyNotifiesObserversOfUpdateCheckInterval
{
    return NO;
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

- (BOOL)currentAutomaticallyDownloadsUpdates SPU_OBJC_DIRECT
{
    return [self allowsAutomaticUpdates] && [_host boolForKey:SUAutomaticallyUpdateKey];
}

- (void)setAutomaticallyDownloadsUpdates:(BOOL)automaticallyDownloadsUpdates
{
    if (![self allowsAutomaticUpdates]) {
        return;
    }
    
    [self willChangeValueForKey:SUAutomaticallyDownloadsUpdatesKeyPath];
    
    _automaticallyDownloadsUpdates = automaticallyDownloadsUpdates;
    [_host setBool:automaticallyDownloadsUpdates forUserDefaultsKey:SUAutomaticallyUpdateKey];
    
    [self didChangeValueForKey:SUAutomaticallyDownloadsUpdatesKeyPath];
}

+ (BOOL)automaticallyNotifiesObserversOfAutomaticallyDownloadsUpdates
{
    return NO;
}

- (BOOL)currentSendsSystemProfile SPU_OBJC_DIRECT
{
    return [_host boolForKey:SUSendProfileInfoKey];
}

- (void)setSendsSystemProfile:(BOOL)sendsSystemProfile
{
    [self willChangeValueForKey:SUSendsSystemProfileKeyPath];
    
    _sendsSystemProfile = sendsSystemProfile;
    [_host setBool:sendsSystemProfile forUserDefaultsKey:SUSendProfileInfoKey];
    
    [self didChangeValueForKey:SUSendsSystemProfileKeyPath];
}

+ (BOOL)automaticallyNotifiesObserversOfSendsSystemProfile
{
    return NO;
}

@end
