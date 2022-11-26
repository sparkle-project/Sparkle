//
//  SUUpdatePermissionResponse.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/8/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUpdatePermissionResponse.h"


#include "AppKitPrevention.h"

static NSString *SUUpdatePermissionAutomaticUpdateChecksKey = @"SUUpdatePermissionAutomaticUpdateChecks";
static NSString *SUUpdatePermissionAutomaticDownloadingUpdatesKey = @"SUUpdatePermissionAutomaticDownloadingUpdates";
static NSString *SUUpdatePermissionSendSystemProfileKey = @"SUUpdatePermissionSendSystemProfile";

@implementation SUUpdatePermissionResponse

@synthesize automaticUpdateChecks = _automaticUpdateChecks;
@synthesize sendSystemProfile = _sendSystemProfile;
@synthesize automaticallyDownloadUpdates = _automaticallyDownloadUpdates;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    BOOL automaticUpdateChecks = [decoder decodeBoolForKey:SUUpdatePermissionAutomaticUpdateChecksKey];
    NSNumber *automaticallyDownloadUpdates = [decoder decodeObjectOfClass:[NSNumber class] forKey:SUUpdatePermissionAutomaticDownloadingUpdatesKey];
    BOOL sendSystemProfile = [decoder decodeBoolForKey:SUUpdatePermissionSendSystemProfileKey];
    return [self initWithAutomaticUpdateChecks:automaticUpdateChecks automaticallyDownloadUpdates:automaticallyDownloadUpdates sendSystemProfile:sendSystemProfile];
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeBool:self.automaticUpdateChecks forKey:SUUpdatePermissionAutomaticUpdateChecksKey];
    
    if (self.automaticallyDownloadUpdates != nil) {
        [encoder encodeObject:self.automaticallyDownloadUpdates forKey:SUUpdatePermissionAutomaticDownloadingUpdatesKey];
    }
    
    [encoder encodeBool:self.sendSystemProfile forKey:SUUpdatePermissionSendSystemProfileKey];
}

- (instancetype)initWithAutomaticUpdateChecks:(BOOL)automaticUpdateChecks automaticallyDownloadUpdates:(NSNumber * _Nullable)automaticallyDownloadUpdates sendSystemProfile:(BOOL)sendSystemProfile
{
    self = [super init];
    if (self != nil) {
        _automaticUpdateChecks = automaticUpdateChecks;
        _automaticallyDownloadUpdates = automaticallyDownloadUpdates;
        _sendSystemProfile = sendSystemProfile;
    }
    return self;
}

- (instancetype)initWithAutomaticUpdateChecks:(BOOL)automaticUpdateChecks sendSystemProfile:(BOOL)sendSystemProfile
{
    return [self initWithAutomaticUpdateChecks:automaticUpdateChecks automaticallyDownloadUpdates:nil sendSystemProfile:sendSystemProfile];
}

@end
