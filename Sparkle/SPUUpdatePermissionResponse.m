//
//  SPUUpdatePermissionResponse.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/8/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUpdatePermissionResponse.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

static NSString *SPUUpdatePermissionAutomaticUpdateChecksKey = @"SPUUpdatePermissionAutomaticUpdateChecks";
static NSString *SPUUpdatePermissionSendSystemProfileKey = @"SPUUpdatePermissionSendSystemProfile";

@implementation SPUUpdatePermissionResponse

@synthesize automaticUpdateChecks = _automaticUpdateChecks;
@synthesize sendSystemProfile = _sendSystemProfile;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    BOOL automaticUpdateChecks = [decoder decodeBoolForKey:SPUUpdatePermissionAutomaticUpdateChecksKey];
    BOOL sendSystemProfile = [decoder decodeBoolForKey:SPUUpdatePermissionSendSystemProfileKey];
    return [self initWithAutomaticUpdateChecks:automaticUpdateChecks sendSystemProfile:sendSystemProfile];
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeBool:self.automaticUpdateChecks forKey:SPUUpdatePermissionAutomaticUpdateChecksKey];
    [encoder encodeBool:self.sendSystemProfile forKey:SPUUpdatePermissionSendSystemProfileKey];
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
