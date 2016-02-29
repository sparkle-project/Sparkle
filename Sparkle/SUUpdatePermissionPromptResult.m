//
//  SUUpdatePermissionPromptResult.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/8/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUpdatePermissionPromptResult.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@implementation SUUpdatePermissionPromptResult

@synthesize choice = _choice;
@synthesize shouldSendProfile = _shouldSendProfile;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    NSInteger choice = [decoder decodeIntegerForKey:@"choice"];
    BOOL shouldSendProfile = [decoder decodeBoolForKey:@"shouldSendProfile"];
    return [[self class] updatePermissionPromptResultWithChoice:choice shouldSendProfile:shouldSendProfile];
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeInteger:self.choice forKey:@"choice"];
    [encoder encodeBool:self.shouldSendProfile forKey:@"shouldSendProfile"];
}

- (instancetype)initWithCheckUpdatesChoice:(SUCheckUpdatesChoice)choice shouldSendProfile:(BOOL)shouldSendProfile
{
    self = [super init];
    if (self != nil) {
        _choice = choice;
        _shouldSendProfile = shouldSendProfile;
    }
    return self;
}

+ (instancetype)updatePermissionPromptResultWithChoice:(SUCheckUpdatesChoice)choice shouldSendProfile:(BOOL)shouldSendProfile
{
    return [[self alloc] initWithCheckUpdatesChoice:choice shouldSendProfile:shouldSendProfile];
}

@end
