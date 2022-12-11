//
//  SPUBasicUpdateDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPUUpdateDriver.h"
#import "SPUUpdateCheck.h"

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

- (instancetype)initWithHost:(SUHost *)host updateCheck:(SPUUpdateCheck)updateCheck updater:(id)updater updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate delegate:(id <SPUBasicUpdateDriverDelegate>)delegate __attribute__((objc_direct));

- (void)setCompletionHandler:(SPUUpdateDriverCompletion)completionBlock __attribute__((objc_direct));

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background __attribute__((objc_direct));

- (void)resumeInstallingUpdate __attribute__((objc_direct));

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate __attribute__((objc_direct));

- (void)abortUpdateAndShowNextUpdateImmediately:(BOOL)shouldSignalShowingUpdate resumableUpdate:(id<SPUResumableUpdate> _Nullable)resumableUpdate error:(nullable NSError *)error __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END
