//
//  SPUDownloadDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUAppcastItem, SUHost, SPUDownloadedUpdate, SPUDownloadData;

@protocol SPUDownloadDriverDelegate <NSObject>

- (void)downloadDriverDidFailToDownloadFileWithError:(NSError *)error;

@optional

- (void)downloadDriverWillBeginDownload;

// For persitent update downloads
- (void)downloadDriverDidDownloadUpdate:(SPUDownloadedUpdate *)downloadedUpdate;

// For temporary downloads
- (void)downloadDriverDidDownloadData:(SPUDownloadData *)downloadData;

// Only for persistent downloads
- (void)downloadDriverDidReceiveExpectedContentLength:(uint64_t)expectedContentLength;

// Only for persistent downloads
- (void)downloadDriverDidReceiveDataOfLength:(uint64_t)length;

@end

@interface SPUDownloadDriver : NSObject

- (instancetype)initWithRequestURL:(NSURL *)requestURL host:(SUHost *)host userAgent:(NSString * _Nullable)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background delegate:(id<SPUDownloadDriverDelegate>)delegate __attribute__((objc_direct));

- (instancetype)initWithUpdateItem:(SUAppcastItem *)updateItem secondaryUpdateItem:(SUAppcastItem * _Nullable)secondaryUpdateItem host:(SUHost *)host userAgent:(NSString * _Nullable)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background delegate:(id<SPUDownloadDriverDelegate>)delegate __attribute__((objc_direct));

- (instancetype)initWithHost:(SUHost *)host __attribute__((objc_direct));

- (void)downloadFile __attribute__((objc_direct));

- (void)removeDownloadedUpdate:(SPUDownloadedUpdate *)downloadedUpdate __attribute__((objc_direct));

@property (nonatomic, readonly, direct) NSMutableURLRequest *request;
@property (nonatomic, readonly, direct) BOOL inBackground;

- (void)cleanup:(void (^)(void))completionHandler __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END
