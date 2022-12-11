//
//  SUPhasedUpdateGroupInfo.m
//  Sparkle
//
//  Created by Mayur Pawashe on 01/24/21.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUPhasedUpdateGroupInfo.h"
#import "SUHost.h"
#import "SUConstants.h"


#include "AppKitPrevention.h"

@implementation SUPhasedUpdateGroupInfo

#define NUM_UPDATE_GROUPS 7
+ (NSUInteger)updateGroupForHost:(SUHost*)host
{
    NSNumber* updateGroupIdentifier = [self updateGroupIdentifierForHost:host];
    return ([updateGroupIdentifier unsignedIntValue] % NUM_UPDATE_GROUPS);
}

+ (NSNumber*)updateGroupIdentifierForHost:(SUHost*)host SPU_OBJC_DIRECT
{
    NSNumber* updateGroupIdentifier = [host objectForUserDefaultsKey:SUUpdateGroupIdentifierKey];
    if(updateGroupIdentifier == nil) {
        updateGroupIdentifier = [self setNewUpdateGroupIdentifierForHost:host];
    }

    return updateGroupIdentifier;
}

+ (NSNumber*)setNewUpdateGroupIdentifierForHost:(SUHost*)host
{
    unsigned int r = arc4random_uniform(UINT_MAX);
    NSNumber* updateGroupIdentifier = @(r);

    [host setObject:updateGroupIdentifier forUserDefaultsKey:SUUpdateGroupIdentifierKey];

    return updateGroupIdentifier;
}

@end
