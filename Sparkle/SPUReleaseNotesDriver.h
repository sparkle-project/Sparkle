//
//  SPUReleaseNotesDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPUDownloadDriver.h"

NS_ASSUME_NONNULL_BEGIN

@class SUHost, SUSignatures, SPUDownloadData;

// Downloads and (if required) verifies release notes data for a found update
SPU_OBJC_DIRECT_MEMBERS @interface SPUReleaseNotesDriver : NSObject <SPUDownloadDriverDelegate>

- (instancetype)initWithReleaseNotesURL:(NSURL *)releaseNotesURL contentLength:(uint64_t)contentLength signatures:(SUSignatures * _Nullable)signatures httpHeaders:(NSDictionary * _Nullable)httpHeaders userAgent:(NSString * _Nullable)userAgent host:(SUHost *)host completionHandler:(void (^)(SPUDownloadData * _Nullable, NSError * _Nullable))completionHandler;

- (void)startDownload;

- (void)cleanup:(void (^)(void))cleanupHandler;

@end

NS_ASSUME_NONNULL_END
