//
//  SUUpdateDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

typedef void (^SUUpdateDriverCompletion)(BOOL shouldShowUpdateImmediately);

@protocol SUUpdateDriver <NSObject>

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders completion:(SUUpdateDriverCompletion)completionBlock;

- (void)resumeUpdateWithCompletion:(SUUpdateDriverCompletion)completionBlock;

- (void)abortUpdate;

@end

NS_ASSUME_NONNULL_END
