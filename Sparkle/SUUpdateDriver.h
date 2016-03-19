//
//  SUUpdateDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@protocol SUUpdateDriver <NSObject>

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders completion:(void (^)(void))completionBlock;

- (void)abortUpdate;

@end

NS_ASSUME_NONNULL_END
