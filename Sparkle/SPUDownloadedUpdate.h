//
//  SPUDownloadedUpdate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 1/8/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPUResumableUpdate.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPUDownloadedUpdate : NSObject <SPUResumableUpdate>

- (instancetype)initWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryItem downloadName:(NSString *)downloadName temporaryDirectory:(NSString *)temporaryDirectory __attribute__((objc_direct));

@property (nonatomic, copy, readonly, direct) NSString *downloadName;
@property (nonatomic, copy, readonly, direct) NSString *temporaryDirectory;

@end

NS_ASSUME_NONNULL_END
