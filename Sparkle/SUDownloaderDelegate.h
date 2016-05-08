//
//  SUDownloaderDelegate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SUDownloaderDelegate <NSObject>

- (void)downloaderDidSetDestinationName:(NSString *)destinationName temporaryDirectory:(NSString *)temporaryDirectory;

- (void)downloaderDidReceiveResponse:(NSURLResponse *)response;

- (void)downloaderDidReceiveDataOfLength:(NSUInteger)length;

- (void)downloaderDidFinishDownloading;

- (void)downloaderDidFailWithError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
