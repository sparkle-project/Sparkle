//
//  SPUUpdatePermission.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/8/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUpdatePermission.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

static NSString *SPUUpdatePermissionChoiceKey = @"SPUUpdatePermissionChoice";
static NSString *SPUUpdatePermissionSendProfileKey = @"SPUUpdatePermissionSendProfile";

@implementation SPUUpdatePermission

@synthesize choice = _choice;
@synthesize sendProfile = _sendProfile;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    NSInteger choice = [decoder decodeIntegerForKey:SPUUpdatePermissionChoiceKey];
    BOOL sendProfile = [decoder decodeBoolForKey:SPUUpdatePermissionSendProfileKey];
    return [[self class] updatePermissionWithChoice:choice sendProfile:sendProfile];
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeInteger:self.choice forKey:SPUUpdatePermissionChoiceKey];
    [encoder encodeBool:self.sendProfile forKey:SPUUpdatePermissionSendProfileKey];
}

- (instancetype)initWithCheckUpdatesChoice:(SPUCheckUpdatesChoice)choice sendProfile:(BOOL)sendProfile
{
    self = [super init];
    if (self != nil) {
        _choice = choice;
        _sendProfile = sendProfile;
    }
    return self;
}

+ (instancetype)updatePermissionWithChoice:(SPUCheckUpdatesChoice)choice sendProfile:(BOOL)sendProfile
{
    return [[self alloc] initWithCheckUpdatesChoice:choice sendProfile:sendProfile];
}

@end
