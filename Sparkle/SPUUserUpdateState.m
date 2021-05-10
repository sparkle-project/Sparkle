//
//  SPUUserUpdateState.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/9/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SPUUserUpdateState.h"
#import "SPUUserUpdateState+Private.h"


#include "AppKitPrevention.h"

@implementation SPUUserUpdateState

@synthesize stage = _stage;
@synthesize userInitiated = _userInitiated;
@synthesize majorUpgrade = _majorUpgrade;

- (instancetype)initWithStage:(SPUUserUpdateStage)stage userInitiated:(BOOL)userInitiated majorUpgrade:(BOOL)majorUpgrade
{
    self = [super init];
    if (self != nil) {
        _stage = stage;
        _userInitiated = userInitiated;
        _majorUpgrade = majorUpgrade;
    }
    return self;
}

@end
