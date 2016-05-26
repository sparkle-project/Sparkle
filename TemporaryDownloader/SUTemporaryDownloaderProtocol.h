//
//  SUTemporaryDownloaderProtocol.h
//  TemporaryDownloader
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUURLRequest;

// The protocol that this service will vend as its API. This header file will also need to be visible to the process hosting the service.
@protocol SUTemporaryDownloaderProtocol

- (void)startDownloadWithRequest:(SUURLRequest *)request completion:(void (^)(NSData * _Nullable data, NSError * _Nullable error))completionBlock;

@end

NS_ASSUME_NONNULL_END
