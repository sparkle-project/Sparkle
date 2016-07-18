//
//  SUInstallerProgressLauncherProtocol.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUInstallerAgentInitiationProtocol.h"
#import "SUAuthorizationReply.h"

NS_ASSUME_NONNULL_BEGIN

@protocol SUInstallerProgressLauncherProtocol <SUInstallerAgentInitiationProtocol>

- (void)requestUserAuthorizationWithReply:(void (^)(SUAuthorizationReply))reply;

// Redeclare this method from SUInstallerAgentInitiationProtocol because XPC decoders on older OS systems (eg: 10.8) do not traverse parent protocols
- (void)connectionDidInitiateWithReply:(void (^)(void))acknowledgement;

@end

NS_ASSUME_NONNULL_END
