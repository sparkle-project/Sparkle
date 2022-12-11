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

- (void)uiDriverDidShowUpdate;
- (void)basicDriverDidFinishLoadingAppcast;

@end

@class SUHost;
@protocol SPUUserDriver, SPUUpdaterDelegate;

@interface SPUUIBasedUpdateDriver : NSObject

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver userInitiated:(BOOL)userInitiated updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate delegate:(id<SPUUIBasedUpdateDriverDelegate>)delegate __attribute__((objc_direct));

- (void)setCompletionHandler:(SPUUpdateDriverCompletion)completionBlock __attribute__((objc_direct));

- (void)setUpdateWillInstallHandler:(void (^)(void))updateWillInstallHandler __attribute__((objc_direct));

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background __attribute__((objc_direct));

- (void)resumeInstallingUpdate __attribute__((objc_direct));

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate __attribute__((objc_direct));

- (void)abortUpdateWithError:(nullable NSError *)error showErrorToUser:(BOOL)showedUserProgress __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END
