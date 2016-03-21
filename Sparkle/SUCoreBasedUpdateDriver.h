//
//  SUCoreBasedUpdateDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUStatusCompletionResults.h"
#import "SUUpdateDriver.h"

NS_ASSUME_NONNULL_BEGIN

@class SUHost, SUAppcastItem;
@protocol SUUpdaterDelegate;

@protocol SUCoreBasedUpdateDriverDelegate <NSObject>

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)updateItem;

- (void)installerDidFinishRelaunchPreparation;

- (void)coreDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error;

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error;

- (BOOL)basicDriverShouldSignalShowingUpdateImmediately;

@optional

- (void)basicDriverDidFinishLoadingAppcast;

- (void)coreDriverDidFinishDownloadingUpdate;

- (void)installerDidStartInstalling;

- (void)installerDidExtractUpdateWithProgress:(double)progress;

- (void)coreDriverIsRequestingAppTermination;

@end

@interface SUCoreBasedUpdateDriver : NSObject

- (instancetype)initWithHost:(SUHost *)host sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater updaterDelegate:(nullable id <SUUpdaterDelegate>)updaterDelegate delegate:(id<SUCoreBasedUpdateDriverDelegate>)delegate;

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders includesSkippedUpdates:(BOOL)includesSkippedUpdates completion:(SUUpdateDriverCompletion)completionBlock;

- (void)resumeUpdateWithCompletion:(SUUpdateDriverCompletion)completionBlock;

- (void)downloadUpdateFromAppcastItem:(SUAppcastItem *)updateItem;

- (void)finishInstallationWithResponse:(SUInstallUpdateStatus)installUpdateStatus;

- (void)abortUpdateWithError:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
