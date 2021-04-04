//
//  SUXPCInstallerConnection.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUXPCInstallerConnection.h"


#include "AppKitPrevention.h"

@interface SUXPCInstallerConnection ()

@property (nonatomic) NSXPCConnection *connection;
@property (nonatomic) id<SUInstallerCommunicationProtocol> delegate; // intentionally not weak for XPC reasons
@property (nonatomic, copy) void (^invalidationBlock)(void);

@end

@implementation SUXPCInstallerConnection

@synthesize connection = _connection;
@synthesize delegate = _delegate;
@synthesize invalidationBlock = _invalidationBlock;

- (instancetype)initWithDelegate:(id<SUInstallerCommunicationProtocol>)delegate
{
    self = [super init];
    if (self != nil) {
        _connection = [[NSXPCConnection alloc] initWithServiceName:@INSTALLER_CONNECTION_BUNDLE_ID];
        _connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerConnectionProtocol)];
        
        __weak SUXPCInstallerConnection *weakSelf = self;
        _connection.invalidationHandler = ^{
            [weakSelf invokeInvalidation];
        };
        
        _connection.interruptionHandler = ^{
            [weakSelf invokeInvalidation];
            [weakSelf.connection invalidate];
        };
        
        _delegate = delegate;
        
        _connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerCommunicationProtocol)];
        _connection.exportedObject = _delegate;
        
        [_connection resume];
    }
    return self;
}

- (void)setInvalidationHandler:(void (^)(void))invalidationHandler
{
    self.invalidationBlock = invalidationHandler;
    
    __weak SUXPCInstallerConnection *weakSelf = self;
    [(id<SUInstallerConnectionProtocol>)self.connection.remoteObjectProxy setInvalidationHandler:^{
        [weakSelf invokeInvalidation];
    }];
}

- (void)setServiceName:(NSString *)serviceName systemDomain:(BOOL)systemDomain
{
    [(id<SUInstallerConnectionProtocol>)self.connection.remoteObjectProxy setServiceName:serviceName systemDomain:systemDomain];
}

- (void)handleMessageWithIdentifier:(int32_t)identifier data:(NSData *)data
{
    [(id<SUInstallerConnectionProtocol>)self.connection.remoteObjectProxy handleMessageWithIdentifier:identifier data:data];
}

- (void)invalidate
{
    [(id<SUInstallerConnectionProtocol>)self.connection.remoteObjectProxy invalidate];
    [self.connection invalidate];
    self.connection = nil;
}

- (void)invokeInvalidation
{
    if (self.invalidationBlock != nil) {
        self.invalidationBlock();
        self.invalidationBlock = nil;
    }
    // Break our retain cycle
    self.delegate = nil;
}

@end
