//
//  SUXPCRemoteMessagePort.h
//  Sparkle
//
//  Created by Mayur Pawashe on 4/3/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SURemoteMessagePortProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface SUXPCRemoteMessagePort : NSObject <SURemoteMessagePortProtocol>

- (instancetype)initWithServiceName:(NSString *)serviceName;

@end

NS_ASSUME_NONNULL_END
