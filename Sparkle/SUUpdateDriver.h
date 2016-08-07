//
//  SUUpdateDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@class SUDownloadedUpdate;

typedef void (^SUUpdateDriverCompletion)(BOOL shouldShowUpdateImmediately, SUDownloadedUpdate * _Nullable resumableUpdate);

@protocol SUUpdateDriver <NSObject>

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders completion:(SUUpdateDriverCompletion)completionBlock;

- (void)resumeInstallingUpdateWithCompletion:(SUUpdateDriverCompletion)completionBlock;

- (void)resumeDownloadedUpdate:(SUDownloadedUpdate *)downloadedUpdate completion:(SUUpdateDriverCompletion)completionBlock;

- (void)abortUpdate;

@end

NS_ASSUME_NONNULL_END
