//
//  SPUAppcastItemState.h
//  Sparkle
//
//  Created by Mayur Pawashe on 5/31/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Appcast Item state that contains properties that depends on a host
@interface SPUAppcastItemState : NSObject

- (instancetype)init NS_UNAVAILABLE;

- (instancetype)initWithMajorUpgrade:(BOOL)majorUpgrade criticalUpdate:(BOOL)criticalUpdate informationalUpdate:(BOOL)informationalUpdate minimumOperatingSystemVersionIsOK:(BOOL)minimumOperatingSystemVersionIsOK maximumOperatingSystemVersionIsOK:(BOOL)maximumOperatingSystemVersionIsOK __attribute__((objc_direct));

@property (nonatomic, readonly, direct) BOOL majorUpgrade;
@property (nonatomic, readonly, direct) BOOL criticalUpdate;
@property (nonatomic, readonly, direct) BOOL informationalUpdate;
@property (nonatomic, readonly, direct) BOOL minimumOperatingSystemVersionIsOK;
@property (nonatomic, readonly, direct) BOOL maximumOperatingSystemVersionIsOK;

@end

NS_ASSUME_NONNULL_END
