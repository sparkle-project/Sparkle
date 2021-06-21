//
//  SPUAppcastItemState.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/31/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SPUAppcastItemState.h"


#include "AppKitPrevention.h"

#define SPUAppcastItemStateMajorUpgradeKey @"SPUAppcastItemStateMajorUpgrade"
#define SPUAppcastItemStateCriticalUpdateKey @"SPUAppcastItemStateCriticalUpdate"
#define SPUAppcastItemStateInformationalUpdateKey @"SPUAppcastItemStateInformationalUpdate"
#define SPUAppcastItemStateMinimumOperatingSystemVersionIsOKKey @"SPUAppcastItemStateMinimumOperatingSystemVersionIsOK"
#define SPUAppcastItemStateMaximumOperatingSystemVersionIsOKKey @"SPUAppcastItemStateMaximumOperatingSystemVersionIsOK"

@interface SPUAppcastItemState () <NSSecureCoding>
@end

@implementation SPUAppcastItemState

@synthesize majorUpgrade = _majorUpgrade;
@synthesize criticalUpdate = _criticalUpdate;
@synthesize informationalUpdate = _informationalUpdate;
@synthesize minimumOperatingSystemVersionIsOK = _minimumOperatingSystemVersionIsOK;
@synthesize maximumOperatingSystemVersionIsOK = _maximumOperatingSystemVersionIsOK;

- (instancetype)initWithMajorUpgrade:(BOOL)majorUpgrade criticalUpdate:(BOOL)criticalUpdate informationalUpdate:(BOOL)informationalUpdate minimumOperatingSystemVersionIsOK:(BOOL)minimumOperatingSystemVersionIsOK maximumOperatingSystemVersionIsOK:(BOOL)maximumOperatingSystemVersionIsOK
{
    self = [super init];
    if (self != nil) {
        _majorUpgrade = majorUpgrade;
        _criticalUpdate = criticalUpdate;
        _informationalUpdate = informationalUpdate;
        _minimumOperatingSystemVersionIsOK = minimumOperatingSystemVersionIsOK;
        _maximumOperatingSystemVersionIsOK = maximumOperatingSystemVersionIsOK;
    }
    return self;
}

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeBool:self.majorUpgrade forKey:SPUAppcastItemStateMajorUpgradeKey];
    [encoder encodeBool:self.criticalUpdate forKey:SPUAppcastItemStateCriticalUpdateKey];
    [encoder encodeBool:self.informationalUpdate forKey:SPUAppcastItemStateInformationalUpdateKey];
    [encoder encodeBool:self.minimumOperatingSystemVersionIsOK forKey:SPUAppcastItemStateMinimumOperatingSystemVersionIsOKKey];
    [encoder encodeBool:self.maximumOperatingSystemVersionIsOK forKey:SPUAppcastItemStateMaximumOperatingSystemVersionIsOKKey];
}

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    BOOL majorUpgrade = [decoder decodeBoolForKey:SPUAppcastItemStateMajorUpgradeKey];
    BOOL criticalUpdate = [decoder decodeBoolForKey:SPUAppcastItemStateCriticalUpdateKey];
    BOOL informationalUpdate = [decoder decodeBoolForKey:SPUAppcastItemStateInformationalUpdateKey];
    BOOL minimumOperatingSystemVersionIsOK = [decoder decodeBoolForKey:SPUAppcastItemStateMinimumOperatingSystemVersionIsOKKey];
    BOOL maximumOperatingSystemVersionIsOK = [decoder decodeBoolForKey:SPUAppcastItemStateMaximumOperatingSystemVersionIsOKKey];
    
    return [self initWithMajorUpgrade:majorUpgrade criticalUpdate:criticalUpdate informationalUpdate:informationalUpdate minimumOperatingSystemVersionIsOK:minimumOperatingSystemVersionIsOK maximumOperatingSystemVersionIsOK:maximumOperatingSystemVersionIsOK];
}

@end
