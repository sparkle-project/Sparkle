//
//  SULocalMessagePort.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/9/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SULocalMessagePort : NSObject

// Note: messageCallback may not be called on the main thread
- (nullable instancetype)initWithServiceName:(NSString *)serviceName messageCallback:(NSData *(^)(int32_t identifier, NSData *data))messageCallback invalidationCallback:(void (^)(void))invalidationCallback;

- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
