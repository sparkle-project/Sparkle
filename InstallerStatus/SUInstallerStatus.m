//
//  SUInstallerStatus.m
//  InstallerStatus
//
//  Created by Mayur Pawashe on 7/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUInstallerStatus.h"


#include "AppKitPrevention.h"

@interface SUInstallerStatus ()

@property (nonatomic, copy) void (^invalidationBlock)(void);
@property (nonatomic) NSXPCConnection *connection;

@end

@implementation SUInstallerStatus

@synthesize invalidationBlock = _invalidationBlock;
@synthesize connection = _connection;

- (void)setInvalidationHandler:(void (^)(void))invalidationHandler
{
    self.invalidationBlock = invalidationHandler;
}

- (void)setServiceName:(NSString *)serviceName
{
    NSXPCConnection *connection = [[NSXPCConnection alloc] initWithMachServiceName:serviceName options:(NSXPCConnectionOptions)0];
    
    connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUStatusInfoProtocol)];
    
    self.connection = connection;
    
    __weak SUInstallerStatus *weakSelf = self;
    self.connection.interruptionHandler = ^{
        [weakSelf.connection invalidate];
    };
    
    self.connection.invalidationHandler = ^{
        SUInstallerStatus *strongSelf = weakSelf;
        if (strongSelf != nil) {
            strongSelf.connection = nil;
            [strongSelf invalidate];
        }
    };
    
    [self.connection resume];
}

- (void)probeStatusInfoWithReply:(void (^)(NSData * _Nullable installationInfoData))reply
{
    [(id<SUStatusInfoProtocol>)self.connection.remoteObjectProxy probeStatusInfoWithReply:reply];
}

- (void)probeStatusConnectivityWithReply:(void (^)(void))reply
{
    [(id<SUStatusInfoProtocol>)self.connection.remoteObjectProxy probeStatusConnectivityWithReply:reply];
}

// This method can be called by us or from a remote
- (void)invalidate
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.connection invalidate];
        self.connection = nil;
        
        if (self.invalidationBlock != nil) {
            self.invalidationBlock();
            self.invalidationBlock = nil;
        }
    });
}

@end
