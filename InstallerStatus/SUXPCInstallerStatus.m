//
//  SUXPCInstallerStatus.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUXPCInstallerStatus.h"


#include "AppKitPrevention.h"

@interface SUXPCInstallerStatus ()

@property (nonatomic) NSXPCConnection *connection;
@property (nonatomic, copy) void (^invalidationBlock)(void);

@end

@implementation SUXPCInstallerStatus

@synthesize connection = _connection;
@synthesize invalidationBlock = _invalidationBlock;

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _connection = [[NSXPCConnection alloc] initWithServiceName:@INSTALLER_STATUS_BUNDLE_ID];
        _connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerStatusProtocol)];
        
        __weak SUXPCInstallerStatus *weakSelf = self;
        _connection.invalidationHandler = ^{
            [weakSelf invokeInvalidation];
        };
        
        _connection.interruptionHandler = ^{
            [weakSelf invokeInvalidation];
            [weakSelf.connection invalidate];
        };
        
        [_connection resume];
    }
    return self;
}

- (void)setInvalidationHandler:(void (^)(void))invalidationHandler
{
    self.invalidationBlock = invalidationHandler;
    
    __weak SUXPCInstallerStatus *weakSelf = self;
    [(id<SUInstallerStatusProtocol>)self.connection.remoteObjectProxy setInvalidationHandler:^{
        [weakSelf invokeInvalidation];
    }];
}

- (void)setServiceName:(NSString *)serviceName
{
    [(id<SUInstallerStatusProtocol>)self.connection.remoteObjectProxy setServiceName:serviceName];
}

- (void)probeStatusInfoWithReply:(void (^)(NSData * _Nullable installationInfoData))reply
{
    [(id<SUInstallerStatusProtocol>)self.connection.remoteObjectProxy probeStatusInfoWithReply:reply];
}

- (void)probeStatusConnectivityWithReply:(void (^)(void))reply
{
    [(id<SUInstallerStatusProtocol>)self.connection.remoteObjectProxy probeStatusConnectivityWithReply:reply];
}

- (void)invalidate
{
    [(id<SUInstallerStatusProtocol>)self.connection.remoteObjectProxy invalidate];
    [self.connection invalidate];
    self.connection = nil;
}

- (void)invokeInvalidation
{
    if (self.invalidationBlock != nil) {
        self.invalidationBlock();
        self.invalidationBlock = nil;
    }
}

@end
