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

- (void)setInvalidationHandler:(void (^)(void))invalidationHandler;

- (void)setServiceName:(NSString *)serviceName;

- (void)invalidate;
    
@end

NS_ASSUME_NONNULL_END
