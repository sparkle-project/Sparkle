//
//  SPUUpdateDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@protocol SPUResumableUpdate;

typedef void (^SPUUpdateDriverCompletion)(BOOL shouldShowUpdateImmediately, id<SPUResumableUpdate> _Nullable resumableUpdate);

@protocol SPUUpdateDriver <NSObject>

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders preventingInstallerInteraction:(BOOL)preventsInstallerInteraction completion:(SPUUpdateDriverCompletion)completionBlock;

- (void)resumeInstallingUpdateWithCompletion:(SPUUpdateDriverCompletion)completionBlock;

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate completion:(SPUUpdateDriverCompletion)completionBlock;

- (void)abortUpdate;
- (void)abortUpdateWithError:(NSError * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
