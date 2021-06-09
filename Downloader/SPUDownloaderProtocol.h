//
//  SPUDownloaderProtocol.h
//  PersistentDownloader
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SPUURLRequest;

// The protocol that this service will vend as its API. This header file will also need to be visible to the process hosting the service.
@protocol SPUDownloaderProtocol

- (void)startPersistentDownloadWithRequest:(SPUURLRequest *)request bundleIdentifier:(NSString *)bundleIdentifier desiredFilename:(NSString *)desiredFilename;

- (void)startTemporaryDownloadWithRequest:(SPUURLRequest *)request;

- (void)removeDownloadDirectory:(NSString *)directoryName bundleIdentifier:(NSString *)bundleIdentifier;

- (void)cleanup:(void (^)(void))completionHandler;

@end

NS_ASSUME_NONNULL_END
