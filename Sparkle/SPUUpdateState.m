//
//  SPUUserUpdateState.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/9/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SPUUpdateState.h"
#import "SPUUpdateState+Private.h"


#include "AppKitPrevention.h"

#define SPUUserUpdateStateStageKey @"SPUUserUpdateStateStage"
#define SPUUserUpdateStateUserInitiatedKey @"SPUUserUpdateStateUserInitiated"
#define SPUUserUpdateStateMajorUpgradeKey @"SPUUserUpdateStateMajorUpgrade"
#define SPUUserUpdateStateCriticalUpdateKey @"SPUUserUpdateStateCriticalUpdate"

@interface SPUUpdateState () <NSSecureCoding>
@end

@implementation SPUUpdateState

@synthesize stage = _stage;
@synthesize userInitiated = _userInitiated;

- (instancetype)initWithStage:(SPUUpdateStage)stage userInitiated:(BOOL)userInitiated
{
    self = [super init];
    if (self != nil) {
        _stage = stage;
        _userInitiated = userInitiated;
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeInteger:self.stage forKey:SPUUserUpdateStateStageKey];
    [encoder encodeBool:self.userInitiated forKey:SPUUserUpdateStateUserInitiatedKey];
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    SPUUpdateStage stage = [decoder decodeIntegerForKey:SPUUserUpdateStateStageKey];
    BOOL userInitiated = [decoder decodeBoolForKey:SPUUserUpdateStateUserInitiatedKey];
    
    return [self initWithStage:stage userInitiated:userInitiated];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

@end
