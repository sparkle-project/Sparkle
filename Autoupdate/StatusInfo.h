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

__attribute__((objc_direct_members)) @interface StatusInfo : NSObject <SUStatusInfoProtocol>

- (instancetype)initWithHostBundleIdentifier:(NSString *)bundleIdentifier;

@property (nonatomic, nullable) NSData *installationInfoData;

- (void)startListener;

- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
