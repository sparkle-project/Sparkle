//
//  SUUpdatePermissionPromptResult.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/8/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUpdatePermissionPromptResult.h"

@implementation SUUpdatePermissionPromptResult

@synthesize choice = _choice;
@synthesize shouldSendProfile = _shouldSendProfile;

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
