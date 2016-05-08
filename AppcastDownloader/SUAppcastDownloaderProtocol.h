//
//  SUAppcastDownloaderProtocol.h
//  AppcastDownloader
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// The protocol that this service will vend as its API. This header file will also need to be visible to the process hosting the service.
@protocol SUAppcastDownloaderProtocol

- (void)startDownloadWithRequest:(NSURLRequest *)request completion:(void (^)(NSData * _Nullable data, NSError * _Nullable error))completionBlock;

@end

NS_ASSUME_NONNULL_END
