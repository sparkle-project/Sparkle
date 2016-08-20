//
//  SUPersistentDownloaderProtocol.h
//  PersistentDownloader
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SPUURLRequest;

typedef NS_ENUM(NSUInteger, SPUDownloadMode)
{
    SPUDownloadModePersistent,
    SPUDownloadModeTemporary
};

// The protocol that this service will vend as its API. This header file will also need to be visible to the process hosting the service.
@protocol SUPersistentDownloaderProtocol

- (void)startDownloadWithRequest:(SPUURLRequest *)request mode:(SPUDownloadMode)mode bundleIdentifier:(NSString *)bundleIdentifier desiredFilename:(NSString *)desiredFilename;

@end

NS_ASSUME_NONNULL_END
