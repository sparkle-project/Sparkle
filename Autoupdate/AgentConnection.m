//
//  AgentConnection.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "AgentConnection.h"
#import "SUMessageTypes.h"
#import "SUInstallerAgentProtocol.h"
#import "SUInstallerAgentInitiationProtocol.h"

#ifdef _APPKITDEFINES_H
#error This is a "daemon-safe" class and should NOT import AppKit
#endif

@interface AgentConnection () <NSXPCListenerDelegate, SUInstallerAgentInitiationProtocol>

@property (nonatomic) NSXPCListener *xpcListener;
@property (nonatomic, nullable) NSXPCConnection *activeConnection;
@property (nonatomic, nullable) id<SUInstallerAgentProtocol> agent;
@property (nonatomic, weak) id<AgentConnectionDelegate> delegate;
@property (nonatomic) BOOL connected;

@end

@implementation AgentConnection

@synthesize xpcListener = _xpcListener;
@synthesize activeConnection = _activeConnection;
@synthesize agent = _agent;
@synthesize delegate = _delegate;
@synthesize connected = _connected;

- (instancetype)initWithHostBundleIdentifier:(NSString *)bundleIdentifier delegate:(id<AgentConnectionDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        // Agents should always be the one that connect to daemons due to how mach bootstraps work
        // For this reason, we are the ones that are creating a listener, not the agent
        _xpcListener = [[NSXPCListener alloc] initWithMachServiceName:SUProgressAgentServiceNameForBundleIdentifier(bundleIdentifier)];
        _xpcListener.delegate = self;
        _delegate = delegate;
    }
    return self;
}

- (void)startListener
{
    [self.xpcListener resume];
}

- (void)invalidate
{
    self.delegate = nil;
    
    [self.activeConnection invalidate];
    self.activeConnection = nil;
    
    [self.xpcListener invalidate];
    self.xpcListener = nil;
}

- (BOOL)listener:(NSXPCListener *)__unused listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection
{
    if (self.activeConnection != nil) {
        [newConnection invalidate];
        return NO;
    }
    
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerAgentInitiationProtocol)];
    newConnection.exportedObject = self;
    
    newConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerAgentProtocol)];
    
    self.activeConnection = newConnection;
    
    __weak AgentConnection *weakSelf = self;
    newConnection.interruptionHandler = ^{
        [weakSelf.activeConnection invalidate];
    };
    
    newConnection.invalidationHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.delegate agentConnectionDidInvalidate];
        });
    };
    
    [newConnection resume];
    
    self.agent = newConnection.remoteObjectProxy;
    
    return YES;
}

- (void)connectionDidInitiateWithReply:(void (^)(void))acknowledgement
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.connected = YES;
        
        [self.delegate agentConnectionDidInitiate];
        self.delegate = nil;
    });
    
    acknowledgement();
}

@end
