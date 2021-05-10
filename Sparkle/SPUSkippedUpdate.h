//
//  SPUSkippedUpdate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 5/8/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUHost, SUAppcastItem;

@interface SPUSkippedUpdate : NSObject

- (instancetype)initWithVersion:(NSString *)version minimumAutoupdateVersion:(nullable NSString *)minimumAutoupdateVersion;

+ (NSArray<SPUSkippedUpdate *> *)skippedUpdatesForHost:(SUHost *)host;
+ (void)clearSkippedUpdatesForHost:(SUHost *)host;
+ (void)skipUpdate:(SUAppcastItem *)updateItem host:(SUHost *)host;

@property (nonatomic, readonly) NSString *version;
@property (nonatomic, readonly, nullable) NSString *minimumAutoupdateVersion;

@end

NS_ASSUME_NONNULL_END
