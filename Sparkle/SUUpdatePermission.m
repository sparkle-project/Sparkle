//
//  SUUpdatePermission.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/8/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUpdatePermission.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

static NSString *SUUpdatePermissionChoiceKey = @"SUUpdatePermissionChoice";
static NSString *SUUpdatePermissionSendProfileKey = @"SUUpdatePermissionSendProfile";

@implementation SUUpdatePermission

@synthesize choice = _choice;
@synthesize sendProfile = _sendProfile;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    NSInteger choice = [decoder decodeIntegerForKey:SUUpdatePermissionChoiceKey];
    BOOL sendProfile = [decoder decodeBoolForKey:SUUpdatePermissionSendProfileKey];
    return [[self class] updatePermissionWithChoice:choice sendProfile:sendProfile];
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeInteger:self.choice forKey:SUUpdatePermissionChoiceKey];
    [encoder encodeBool:self.sendProfile forKey:SUUpdatePermissionSendProfileKey];
}

- (instancetype)initWithCheckUpdatesChoice:(SUCheckUpdatesChoice)choice sendProfile:(BOOL)sendProfile
{
    self = [super init];
    if (self != nil) {
        _choice = choice;
        _sendProfile = sendProfile;
    }
    return self;
}

+ (instancetype)updatePermissionWithChoice:(SUCheckUpdatesChoice)choice sendProfile:(BOOL)sendProfile
{
    return [[self alloc] initWithCheckUpdatesChoice:choice sendProfile:sendProfile];
}

@end
