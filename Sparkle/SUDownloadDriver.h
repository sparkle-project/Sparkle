//
//  SUDownloadDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUAppcastItem, SUHost, SUDownloadedUpdate;

@protocol SUDownloadDriverDelegate <NSObject>

- (void)downloadDriverWillBeginDownload;

- (void)downloadDriverDidReceiveExpectedContentLength:(NSUInteger)expectedContentLength;

- (void)downloadDriverDidReceiveDataOfLength:(NSUInteger)length;

- (void)downloadDriverDidDownloadUpdate:(SUDownloadedUpdate *)downloadedUpdate;

- (void)downloadDriverDidFailToDownloadUpdateWithError:(NSError *)error;

@end

@interface SUDownloadDriver : NSObject

- (instancetype)initWithUpdateItem:(SUAppcastItem *)updateItem host:(SUHost *)host userAgent:(NSString *)userAgent delegate:(id<SUDownloadDriverDelegate>)delegate;

- (void)downloadUpdate;

@property (nonatomic, readonly) NSMutableURLRequest *request;

- (void)cleanup;

@end

NS_ASSUME_NONNULL_END
