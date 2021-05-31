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

@implementation SPUUpdateState

@synthesize stage = _stage;
@synthesize userInitiated = _userInitiated;
@synthesize majorUpgrade = _majorUpgrade;
@synthesize criticalUpdate = _criticalUpdate;

- (instancetype)initWithStage:(SPUUpdateStage)stage userInitiated:(BOOL)userInitiated majorUpgrade:(BOOL)majorUpgrade criticalUpdate:(BOOL)criticalUpdate
{
    self = [super init];
    if (self != nil) {
        _stage = stage;
        _userInitiated = userInitiated;
        _majorUpgrade = majorUpgrade;
        _criticalUpdate = criticalUpdate;
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeInteger:self.stage forKey:SPUUserUpdateStateStageKey];
    [encoder encodeBool:self.userInitiated forKey:SPUUserUpdateStateUserInitiatedKey];
    [encoder encodeBool:self.majorUpgrade forKey:SPUUserUpdateStateMajorUpgradeKey];
    [encoder encodeBool:self.criticalUpdate forKey:SPUUserUpdateStateCriticalUpdateKey];
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    SPUUpdateStage stage = [decoder decodeIntegerForKey:SPUUserUpdateStateStageKey];
    BOOL userInitiated = [decoder decodeBoolForKey:SPUUserUpdateStateUserInitiatedKey];
    BOOL majorUpgrade = [decoder decodeBoolForKey:SPUUserUpdateStateMajorUpgradeKey];
    BOOL criticalUpdate = [decoder decodeBoolForKey:SPUUserUpdateStateCriticalUpdateKey];
    
    return [self initWithStage:stage userInitiated:userInitiated majorUpgrade:majorUpgrade criticalUpdate:criticalUpdate];
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

@end
