//
//  SPUDownloadedUpdate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUAppcastItem;

@interface SPUDownloadedUpdate : NSObject

- (instancetype)initWithAppcastItem:(SUAppcastItem *)updateItem downloadName:(NSString *)downloadName temporaryDirectory:(NSString *)temporaryDirectory;

// For information only updates
- (instancetype)initWithAppcastItem:(SUAppcastItem *)updateItem;

@property (nonatomic, readonly) SUAppcastItem *updateItem;

// These are nil when the update item is just informational and no download is linked
@property (nonatomic, copy, nullable, readonly) NSString *downloadName;
@property (nonatomic, copy, nullable, readonly) NSString *temporaryDirectory;

@end

NS_ASSUME_NONNULL_END
