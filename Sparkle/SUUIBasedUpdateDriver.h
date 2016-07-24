//
//  SUUIBasedUpdateDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUUpdateDriver.h"

NS_ASSUME_NONNULL_BEGIN

@protocol SUUIBasedUpdateDriverDelegate <NSObject>

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error;
- (void)uiDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error;

@optional

- (void)basicDriverDidFinishLoadingAppcast;

@end

@class SUHost, SUDownloadedUpdate;
@protocol SUUserDriver, SUUpdaterDelegate;

@interface SUUIBasedUpdateDriver : NSObject

- (instancetype)initWithHost:(SUHost *)host sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater userDriver:(id <SUUserDriver>)userDriver updaterDelegate:(nullable id <SUUpdaterDelegate>)updaterDelegate delegate:(id<SUUIBasedUpdateDriverDelegate>)delegate;

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders includesSkippedUpdates:(BOOL)includesSkippedUpdates completion:(SUUpdateDriverCompletion)completionBlock;

- (void)resumeInstallingUpdateWithCompletion:(SUUpdateDriverCompletion)completionBlock;

- (void)resumeDownloadedUpdate:(SUDownloadedUpdate *)downloadedUpdate completion:(SUUpdateDriverCompletion)completionBlock;

- (void)abortUpdateWithError:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
