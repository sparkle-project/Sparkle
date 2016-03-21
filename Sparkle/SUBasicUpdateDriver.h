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
@protocol SUUpdaterDelegate;

@protocol SUBasicUpdateDriverDelegate <NSObject>

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)appcastItem;

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error;

- (BOOL)basicDriverShouldSignalShowingUpdateImmediately;

@optional

- (void)basicDriverDidFinishLoadingAppcast;

@end

@interface SUBasicUpdateDriver : NSObject

- (instancetype)initWithHost:(SUHost *)host updater:(id)updater updaterDelegate:(nullable id <SUUpdaterDelegate>)updaterDelegate delegate:(id <SUBasicUpdateDriverDelegate>)delegate;

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders includesSkippedUpdates:(BOOL)includesSkippedUpdates completion:(SUUpdateDriverCompletion)completionBlock;

- (void)resumeUpdateWithCompletion:(SUUpdateDriverCompletion)completionBlock;

@property (nullable, nonatomic, readonly) SUAppcastItem *nonDeltaUpdateItem;

- (void)abortUpdateWithError:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
