//
//  SUDownloadDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SUDownloadDriverDelegate <NSObject>

- (void)downloadDriverDidReceiveResponse:(NSURLResponse *)response;

- (void)downloadDriverDidReceiveDataOfLength:(NSUInteger)length;

- (void)downloadDriverDidDownloadUpdate;

- (void)downloadDriverDidFailToDownloadUpdateWithError:(NSError *)error;

@end

@class SUAppcastItem, SUHost;

@interface SUDownloadDriver : NSObject

- (instancetype)initWithUpdateItem:(SUAppcastItem *)updateItem host:(SUHost *)host userAgent:(NSString *)userAgent delegate:(id<SUDownloadDriverDelegate>)delegate;

- (void)downloadUpdate;

@property (nonatomic, readonly) NSMutableURLRequest *request;
@property (nullable, nonatomic, readonly, copy) NSString *temporaryDirectory;
@property (nullable, nonatomic, readonly, copy) NSString *downloadPath;

- (void)cleanup;

@end

NS_ASSUME_NONNULL_END
