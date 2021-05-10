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

/*
 A skipped update tracks the version and minimum autoupdate version the user skipped.
 Each minimum autoupdate version is tracked as a separate release / train.
 The intent is that a user choosing to skip a future major update chooses to skip that train's updates,
 but a user choosing to skip a minor update only chooses to skip updates equal or preceding that update.
 */
@interface SPUSkippedUpdate : NSObject

- (instancetype)initWithVersion:(NSString *)version minimumAutoupdateVersion:(nullable NSString *)minimumAutoupdateVersion;

+ (NSArray<SPUSkippedUpdate *> *)skippedUpdatesForHost:(SUHost *)host;
+ (void)clearSkippedUpdatesForHost:(SUHost *)host;
+ (void)skipUpdate:(SUAppcastItem *)updateItem host:(SUHost *)host;

@property (nonatomic, readonly) NSString *version;
@property (nonatomic, readonly, nullable) NSString *minimumAutoupdateVersion;

@end

NS_ASSUME_NONNULL_END
