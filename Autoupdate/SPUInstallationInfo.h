//
//  SPUInstallationInfo.h
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUAppcastItem;

@interface SPUInstallationInfo : NSObject <NSSecureCoding>

- (instancetype)initWithAppcastItem:(SUAppcastItem *)appcastItem canSilentlyInstall:(BOOL)canSilentyInstall __attribute__((objc_direct));

@property (nonatomic, readonly, direct) SUAppcastItem *appcastItem;
@property (nonatomic, readonly, direct) BOOL canSilentlyInstall;

@property (nonatomic, direct) BOOL systemDomain;

@end

NS_ASSUME_NONNULL_END
