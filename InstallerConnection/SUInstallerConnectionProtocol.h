//
//  SUInstallerConnectionProtocol.h
//  InstallerConnection
//
//  Created by Mayur Pawashe on 7/9/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUInstallerCommunicationProtocol.h"

NS_ASSUME_NONNULL_BEGIN

@protocol SUInstallerConnectionProtocol <SUInstallerCommunicationProtocol>

// This method is declared in SUInstallerCommunicationProtocol too, but the XPC decoder on macOS 10.8 doesn't know that
- (void)handleMessageWithIdentifier:(int32_t)identifier data:(NSData *)data;

- (void)setInvalidationHandler:(void (^)(void))invalidationHandler;

- (void)setServiceName:(NSString *)serviceName hostPath:(NSString *)hostPath guided:(BOOL)guided;

- (void)invalidate;
    
@end

NS_ASSUME_NONNULL_END
