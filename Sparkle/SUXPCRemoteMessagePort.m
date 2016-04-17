//
//  SUXPCRemoteMessagePort.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/3/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUXPCRemoteMessagePort.h"
#import "SURemoteMessagePort.h"

@interface SUXPCRemoteMessagePort ()

@property (nonatomic, readonly) NSXPCConnection *connection;
@property (nonatomic, copy) void (^invalidationHandler)(void);

@end

@implementation SUXPCRemoteMessagePort

@synthesize connection = _connection;
@synthesize invalidationHandler = _invalidationHandler;

- (instancetype)initWithServiceName:(NSString *)serviceName
{
    self = [self init];
    if (self != nil) {
        _connection = [[NSXPCConnection alloc] initWithServiceName:@REMOTE_MESSAGE_PORT_BUNDLE_ID];
        _connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SURemoteMessagePort)];
        
        __weak SUXPCRemoteMessagePort *weakSelf = self;
        _connection.invalidationHandler = ^{
            [weakSelf invokeInvalidation];
        };
        
        _connection.interruptionHandler = ^{
            [weakSelf invokeInvalidation];
            [weakSelf.connection invalidate];
        };
        
        [_connection resume];
        
        [self setServiceName:serviceName];
    }
    return self;
}

- (void)setServiceName:(NSString *)serviceName
{
    [self.connection.remoteObjectProxy setServiceName:serviceName];
}

- (void)connectWithLookupCompletion:(void (^)(BOOL))lookupCompletionHandler
{
    [self.connection.remoteObjectProxy connectWithLookupCompletion:^(BOOL success) {
        lookupCompletionHandler(success);
        if (!success) {
            [self.connection invalidate];
        }
    }];
}

- (void)invokeInvalidation
{
    if (self != nil && self.invalidationHandler != nil) {
        self.invalidationHandler();
        self.invalidationHandler = nil;
    }
}

- (void)setInvalidationHandler:(void (^)(void))invalidationHandler
{
    _invalidationHandler = [invalidationHandler copy];
    
    __weak SUXPCRemoteMessagePort *weakSelf = self;
    [self.connection.remoteObjectProxy setInvalidationHandler:^{
        [weakSelf invokeInvalidation];
    }];
}

- (void)sendMessageWithIdentifier:(int32_t)identifier data:(NSData *)data completion:(void (^)(BOOL success))completionHandler
{
    [self.connection.remoteObjectProxy sendMessageWithIdentifier:identifier data:data completion:completionHandler];
}

- (void)sendMessageWithIdentifier:(int32_t)identifier data:(NSData *)data reply:(void (^)(BOOL success, NSData * _Nullable replyData))replyHandler
{
    [self.connection.remoteObjectProxy sendMessageWithIdentifier:identifier data:data reply:replyHandler];
}

- (void)invalidate
{
    [self.connection.remoteObjectProxy invalidate];
    [self.connection invalidate];
}

@end
