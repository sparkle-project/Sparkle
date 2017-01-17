//
//  SUUpdatePermissionResponse.m
//  Sparkle
//
//  Created by Mayur Pawashe on 12/26/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUpdatePermissionResponse.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@implementation SUUpdatePermissionResponse

@synthesize automaticUpdateChecks = _automaticUpdateChecks;
@synthesize sendSystemProfile = _sendSystemProfile;

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
