//
//  SULocalMessagePortProtocol.h
//  Sparkle
//
//  Created by Mayur Pawashe on 6/14/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SULocalMessagePortProtocol <NSObject>

- (void)setServiceName:(NSString *)serviceName;

- (void)setInvalidationCallback:(void (^)(void))invalidationCallback;

- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
