//
//  StatusInfo.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUStatusInfoProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface StatusInfo : NSObject <SUStatusInfoProtocol>

- (instancetype)initWithHostBundleIdentifier:(NSString *)bundleIdentifier __attribute__((objc_direct));

@property (nonatomic, nullable, direct) NSData *installationInfoData;

- (void)startListener __attribute__((objc_direct));

- (void)invalidate __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END
