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
@synthesize majorUpdate = _majorUpdate;

- (instancetype)initWithStage:(SPUUserUpdateStage)stage userInitiated:(BOOL)userInitiated majorUpdate:(BOOL)majorUpdate
{
    self = [super init];
    if (self != nil) {
        _stage = stage;
        _userInitiated = userInitiated;
        _majorUpdate = majorUpdate;
    }
    return self;
}

@end
