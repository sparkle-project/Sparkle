//
//  SPUUIBasedUpdateDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPUUpdateDriver.h"

NS_ASSUME_NONNULL_BEGIN

@protocol SPUUIBasedUpdateDriverDelegate <NSObject>

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error;
- (void)coreDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error;
- (void)uiDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error;

@optional

- (void)basicDriverDidFinishLoadingAppcast;
- (void)uiDriverDidShowUpdate;

@end

@class SUHost;
@protocol SPUUserDriver, SPUUpdaterDelegate;

@interface SPUUIBasedUpdateDriver : NSObject

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver userInitiated:(BOOL)userInitiated updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate delegate:(id<SPUUIBasedUpdateDriverDelegate>)delegate;

- (void)prepareCheckForUpdatesWithCompletion:(SPUUpdateDriverCompletion)completionBlock;

- (void)preflightForUpdatePermissionPreventingInstallerInteraction:(BOOL)preventsInstallerInteraction reply:(void (^)(NSError * _Nullable))reply;

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background includesSkippedUpdates:(BOOL)includesSkippedUpdates;

- (void)resumeInstallingUpdateWithCompletion:(SPUUpdateDriverCompletion)completionBlock;

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate completion:(SPUUpdateDriverCompletion)completionBlock;

- (void)abortUpdateWithError:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
