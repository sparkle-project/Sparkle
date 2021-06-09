//
//  SUInstallerConnection.m
//  InstallerConnection
//
//  Created by Mayur Pawashe on 7/9/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUInstallerConnection.h"


#include "AppKitPrevention.h"

static NSString *SUInstallerConnectionKeepAliveReason = @"Installer Connection Keep Alive";

@interface SUInstallerConnection () <SUInstallerCommunicationProtocol>

// Intentionally not weak for XPC reasons
@property (nonatomic) id<SUInstallerCommunicationProtocol> delegate;

@property (nonatomic) BOOL disabledAutomaticTermination;
@property (nonatomic, copy) void (^invalidationBlock)(void);
@property (nonatomic) NSXPCConnection *connection;

@end

@implementation SUInstallerConnection

@synthesize delegate = _delegate;
@synthesize disabledAutomaticTermination = _disabledAutomaticTermination;
@synthesize invalidationBlock = _invalidationBlock;
@synthesize connection = _connection;

- (instancetype)initWithDelegate:(id<SUInstallerCommunicationProtocol>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
        
        // If we are a XPC service, protect it from being terminated until the invalidation handler is set
        _disabledAutomaticTermination = YES;
        [[NSProcessInfo processInfo] disableAutomaticTermination:SUInstallerConnectionKeepAliveReason];
    }
    return self;
}

- (void)enableAutomaticTermination
{
    if (self.disabledAutomaticTermination) {
        [[NSProcessInfo processInfo] enableAutomaticTermination:SUInstallerConnectionKeepAliveReason];
        self.disabledAutomaticTermination = NO;
    }
}

- (void)setInvalidationHandler:(void (^)(void))invalidationHandler
{
    self.invalidationBlock = invalidationHandler;
    
    // No longer needed because of invalidation callback
    [self enableAutomaticTermination];
}

- (void)setServiceName:(NSString *)serviceName systemDomain:(BOOL)systemDomain
{
    NSXPCConnectionOptions options = systemDomain ? NSXPCConnectionPrivileged : 0;
    NSXPCConnection *connection = [[NSXPCConnection alloc] initWithMachServiceName:serviceName options:options];
    
    connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerCommunicationProtocol)];
    connection.exportedObject = self.delegate;
    
    connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerCommunicationProtocol)];
    
    self.connection = connection;
    
    __weak SUInstallerConnection *weakSelf = self;
    self.connection.interruptionHandler = ^{
        [weakSelf.connection invalidate];
    };
    
    self.connection.invalidationHandler = ^{
        SUInstallerConnection *strongSelf = weakSelf;
        if (strongSelf != nil) {
            strongSelf.connection = nil;
            [strongSelf invalidate];
        }
    };
    
    [self.connection resume];
}

- (void)handleMessageWithIdentifier:(int32_t)identifier data:(NSData *)data
{
    [(id<SUInstallerCommunicationProtocol>)self.connection.remoteObjectProxy handleMessageWithIdentifier:identifier data:data];
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
        
        // Break the retain cycle
        self.delegate = nil;
        
        [self enableAutomaticTermination];
    });
}

@end
