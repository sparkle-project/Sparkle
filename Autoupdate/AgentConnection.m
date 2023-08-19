//
//  AgentConnection.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "AgentConnection.h"
#import "SPUMessageTypes.h"
#import "SPUInstallerAgentProtocol.h"
#import "SUInstallerAgentInitiationProtocol.h"


#include "AppKitPrevention.h"

@interface AgentConnection () <NSXPCListenerDelegate, SUInstallerAgentInitiationProtocol>

@end

@implementation AgentConnection
{
    NSXPCListener *_xpcListener;
    NSXPCConnection *_activeConnection;
    __weak id<AgentConnectionDelegate> _delegate;
}

@synthesize agent = _agent;
@synthesize connected = _connected;
@synthesize invalidationError = _invalidationError;

- (instancetype)initWithHostBundleIdentifier:(NSString *)bundleIdentifier delegate:(id<AgentConnectionDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        // Agents should always be the one that connect to daemons due to how mach bootstraps work
        // For this reason, we are the ones that are creating a listener, not the agent
        _xpcListener = [[NSXPCListener alloc] initWithMachServiceName:SPUProgressAgentServiceNameForBundleIdentifier(bundleIdentifier)];
        _xpcListener.delegate = self;
        _delegate = delegate;
    }
    return self;
}

- (void)startListener
{
    [_xpcListener resume];
}

- (void)invalidate
{
    _delegate = nil;
    
    [_activeConnection invalidate];
    _activeConnection = nil;
    
    [_xpcListener invalidate];
    _xpcListener = nil;
}

- (BOOL)listener:(NSXPCListener *)__unused listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection
{
    if (_activeConnection != nil) {
        [newConnection invalidate];
        return NO;
    }
    
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerAgentInitiationProtocol)];
    newConnection.exportedObject = self;
    
    newConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SPUInstallerAgentProtocol)];
    
    _activeConnection = newConnection;
    
    __weak __typeof__(self) weakSelf = self;
    newConnection.interruptionHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __typeof__(self) strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf->_activeConnection invalidate];
            }
        });
    };
    
    newConnection.invalidationHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __typeof__(self) strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf->_delegate agentConnectionDidInvalidate];
            }
        });
    };
    
    [newConnection resume];
    
    _agent = newConnection.remoteObjectProxy;
    
    return YES;
}

- (void)connectionDidInitiateWithReply:(void (^)(void))acknowledgement
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_connected = YES;
        
        [self->_delegate agentConnectionDidInitiate];
    });
    
    acknowledgement();
}

- (void)connectionWillInvalidateWithError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_invalidationError = error;
    });
}

@end
