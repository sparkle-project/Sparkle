//
//  SPUBasicUpdateDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPUUpdateDriver.h"

NS_ASSUME_NONNULL_BEGIN

@class SUHost, SUAppcastItem;
@protocol SPUUpdaterDelegate;

@protocol SPUBasicUpdateDriverDelegate <NSObject>

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)appcastItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryAppcastItem systemDomain:(NSNumber * _Nullable)systemDomain;

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error;

@optional

- (void)basicDriverDidFinishLoadingAppcast;

@end

@interface SPUBasicUpdateDriver : NSObject

- (instancetype)initWithHost:(SUHost *)host updater:(id)updater updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate delegate:(id <SPUBasicUpdateDriverDelegate>)delegate;

- (void)prepareCheckForUpdatesWithCompletion:(SPUUpdateDriverCompletion)completionBlock;

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background;

- (void)resumeInstallingUpdateWithCompletion:(SPUUpdateDriverCompletion)completionBlock;

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate completion:(SPUUpdateDriverCompletion)completionBlock;

- (void)abortUpdateAndShowNextUpdateImmediately:(BOOL)shouldSignalShowingUpdate resumableUpdate:(id<SPUResumableUpdate> _Nullable)resumableUpdate error:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
