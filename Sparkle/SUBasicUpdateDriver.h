//
//  SUBasicUpdateDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUUpdateDriver.h"

NS_ASSUME_NONNULL_BEGIN

@class SUHost, SUAppcastItem;
@protocol SPUUpdaterDelegate;

@protocol SUBasicUpdateDriverDelegate <NSObject>

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)appcastItem;

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error;

@optional

- (void)basicDriverDidFinishLoadingAppcast;

@end

@interface SUBasicUpdateDriver : NSObject

- (instancetype)initWithHost:(SUHost *)host updater:(id)updater updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate delegate:(id <SUBasicUpdateDriverDelegate>)delegate;

- (void)prepareCheckForUpdatesWithCompletion:(SUUpdateDriverCompletion)completionBlock;

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders includesSkippedUpdates:(BOOL)includesSkippedUpdates;

- (void)resumeInstallingUpdateWithCompletion:(SUUpdateDriverCompletion)completionBlock;

- (void)resumeDownloadedUpdate:(SUDownloadedUpdate *)downloadedUpdate completion:(SUUpdateDriverCompletion)completionBlock;

@property (nullable, nonatomic, readonly) SUAppcastItem *nonDeltaUpdateItem;

- (void)abortUpdateAndShowNextUpdateImmediately:(BOOL)shouldSignalShowingUpdate downloadedUpdate:(SUDownloadedUpdate * _Nullable)downloadedUpdate error:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
