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
static NSString *SUUpdatePermissionSendSystemProfileKey = @"SUUpdatePermissionSendSystemProfile";

@implementation SUUpdatePermissionResponse

@synthesize automaticUpdateChecks = _automaticUpdateChecks;
@synthesize sendSystemProfile = _sendSystemProfile;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    BOOL automaticUpdateChecks = [decoder decodeBoolForKey:SUUpdatePermissionAutomaticUpdateChecksKey];
    BOOL sendSystemProfile = [decoder decodeBoolForKey:SUUpdatePermissionSendSystemProfileKey];
    return [self initWithAutomaticUpdateChecks:automaticUpdateChecks sendSystemProfile:sendSystemProfile];
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeBool:self.automaticUpdateChecks forKey:SUUpdatePermissionAutomaticUpdateChecksKey];
    [encoder encodeBool:self.sendSystemProfile forKey:SUUpdatePermissionSendSystemProfileKey];
}

- (instancetype)initWithAutomaticUpdateChecks:(BOOL)automaticUpdateChecks sendSystemProfile:(BOOL)sendSystemProfile
{
    self = [super init];
    if (self != nil) {
        _automaticUpdateChecks = automaticUpdateChecks;
        _sendSystemProfile = sendSystemProfile;
    }
    return self;
}

@end
