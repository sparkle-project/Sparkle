//
//  SUDownloadedUpdate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUAppcastItem;

@interface SUDownloadedUpdate : NSObject

- (instancetype)initWithAppcastItem:(SUAppcastItem *)updateItem downloadName:(NSString *)downloadName temporaryDirectory:(NSString *)temporaryDirectory;

@property (nonatomic, readonly) SUAppcastItem *updateItem;
@property (nonatomic, copy, readonly) NSString *downloadName;
@property (nonatomic, copy, readonly) NSString *temporaryDirectory;

@end

NS_ASSUME_NONNULL_END
