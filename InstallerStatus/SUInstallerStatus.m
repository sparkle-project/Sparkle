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
{
    BOOL _remote;
}

@synthesize invalidationBlock = _invalidationBlock;
@synthesize connection = _connection;

- (instancetype)initWithRemote:(BOOL)remote
{
    self = [super init];
    if (self != nil) {
        _remote = remote;
    }
    return self;
}

- (void)setInvalidationHandler:(void (^)(void))invalidationHandler
{
    if (_remote) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.invalidationBlock = invalidationHandler;
        });
    } else {
        self.invalidationBlock = invalidationHandler;
    }
}

- (void)_setServiceName:(NSString *)serviceName
{
    NSXPCConnection *connection = [[NSXPCConnection alloc] initWithMachServiceName:serviceName options:(NSXPCConnectionOptions)0];
    
    connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUStatusInfoProtocol)];
    
    self.connection = connection;
    
    __weak SUInstallerStatus *weakSelf = self;
    self.connection.interruptionHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.connection invalidate];
        });
    };
    
    self.connection.invalidationHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            SUInstallerStatus *strongSelf = weakSelf;
            if (strongSelf != nil) {
                strongSelf.connection = nil;
                [strongSelf _invokeInvalidationBlock];
            }
        });
    };
    
    [self.connection resume];
}

- (void)setServiceName:(NSString *)serviceName
{
    if (_remote) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self _setServiceName:serviceName];
        });
    } else {
        [self _setServiceName:serviceName];
    }
}

- (void)probeStatusInfoWithReply:(void (^)(NSData * _Nullable installationInfoData))reply
{
    if (_remote) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [(id<SUStatusInfoProtocol>)self.connection.remoteObjectProxy probeStatusInfoWithReply:reply];
        });
    } else {
        [(id<SUStatusInfoProtocol>)self.connection.remoteObjectProxy probeStatusInfoWithReply:reply];
    }
}

- (void)probeStatusConnectivityWithReply:(void (^)(void))reply
{
    if (_remote) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [(id<SUStatusInfoProtocol>)self.connection.remoteObjectProxy probeStatusConnectivityWithReply:reply];
        });
    } else {
        [(id<SUStatusInfoProtocol>)self.connection.remoteObjectProxy probeStatusConnectivityWithReply:reply];
    }
}

- (void)_invokeInvalidationBlock
{
    if (self.invalidationBlock != nil) {
        self.invalidationBlock();
        self.invalidationBlock = nil;
    }
}

// This method can be called from us or a remote
- (void)invalidate
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.connection invalidate];
        self.connection = nil;
        
        [self _invokeInvalidationBlock];
    });
}

@end
