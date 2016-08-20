//
//  SUPersistentDownloaderDelegate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SPUDownloadData;

@protocol SUPersistentDownloaderDelegate <NSObject>

// This is only invoked for persistent downloads
- (void)downloaderDidSetDestinationName:(NSString *)destinationName temporaryDirectory:(NSString *)temporaryDirectory;

// Under rare cases, this may be called more than once, in which case the current progress should be reset back to 0
- (void)downloaderDidReceiveExpectedContentLength:(int64_t)expectedContentLength;

- (void)downloaderDidReceiveDataOfLength:(NSUInteger)length;

// downloadData is nil if this is a persisent download
- (void)downloaderDidFinishWithTemporaryDownloadData:(SPUDownloadData * _Nullable)downloadData;

- (void)downloaderDidFailWithError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
