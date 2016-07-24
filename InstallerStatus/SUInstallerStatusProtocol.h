//
//  SUInstallerStatusProtocol.h
//  InstallerStatus
//
//  Created by Mayur Pawashe on 7/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUStatusInfoProtocol.h"

NS_ASSUME_NONNULL_BEGIN

// The protocol that this service will vend as its API. This header file will also need to be visible to the process hosting the service.
@protocol SUInstallerStatusProtocol <SUStatusInfoProtocol>

// Include SUStatusInfoProtocol protocol methods because XPC on 10.8 won't know about them
- (void)probeStatusInfoWithReply:(void (^)(NSData * _Nullable installationInfoData))reply;
- (void)probeStatusConnectivityWithReply:(void (^)(void))reply;

- (void)setInvalidationHandler:(void (^)(void))invalidationHandler;

- (void)setServiceName:(NSString *)serviceName;

- (void)invalidate;
    
@end

NS_ASSUME_NONNULL_END
