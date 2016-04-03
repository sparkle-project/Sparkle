//
//  SURemoteMessagePort.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/9/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SURemoteMessagePort : NSObject

- (instancetype)initWithServiceName:(NSString *)serviceName;

- (void)connectWithLookupCompletion:(void (^)(BOOL))lookupCompletionHandler invalidationHandler:(void (^)(void))invalidationHandler;

- (void)sendMessageWithIdentifier:(int32_t)identifier data:(NSData *)data completion:(void (^)(BOOL success))completionHandler;

- (void)sendMessageWithIdentifier:(int32_t)identifier data:(NSData *)data reply:(void (^)(BOOL success, NSData * _Nullable replyData))replyHandler;

- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
