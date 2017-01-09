//
//  SPUDownloadDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUAppcastItem, SUHost, SPUResumableUpdate;

@protocol SPUDownloadDriverDelegate <NSObject>

- (void)downloadDriverWillBeginDownload;

- (void)downloadDriverDidReceiveExpectedContentLength:(uint64_t)expectedContentLength;

- (void)downloadDriverDidReceiveDataOfLength:(uint64_t)length;

- (void)downloadDriverDidDownloadUpdate:(SPUResumableUpdate *)downloadedUpdate;

- (void)downloadDriverDidFailToDownloadUpdateWithError:(NSError *)error;

@end

@interface SPUDownloadDriver : NSObject

- (instancetype)initWithUpdateItem:(SUAppcastItem *)updateItem host:(SUHost *)host userAgent:(NSString *)userAgent delegate:(id<SPUDownloadDriverDelegate>)delegate;

- (void)downloadUpdate;

@property (nonatomic, readonly) NSMutableURLRequest *request;

- (void)cleanup;

@end

NS_ASSUME_NONNULL_END
