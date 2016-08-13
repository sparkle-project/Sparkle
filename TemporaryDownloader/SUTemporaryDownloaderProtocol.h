//
//  SUTemporaryDownloaderProtocol.h
//  TemporaryDownloader
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SPUURLRequest;
@class SPUDownloadData;

// The protocol that this service will vend as its API. This header file will also need to be visible to the process hosting the service.
@protocol SUTemporaryDownloaderProtocol

- (void)startDownloadWithRequest:(SPUURLRequest *)request completion:(void (^)(SPUDownloadData * _Nullable downloadData, NSError * _Nullable error))completionBlock;

@end

NS_ASSUME_NONNULL_END
