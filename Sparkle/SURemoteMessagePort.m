//
//  SURemoteMessagePort.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/9/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SURemoteMessagePort.h"

// Because remote message ports returned to us upon creation can be re-used, we maintain a global table so that
// each instance we create can have its own invalidation block. We really invalidate a port for a service name if
// the number of ports for that service reach 0. If we don't maintain a table, we could run into trouble.
// For instance, invalidating one remote message port could invalidate another.
static NSMutableDictionary<NSString *, NSMutableArray<SURemoteMessagePort *> *> *gMessagePortsTable;
static dispatch_queue_t gMessageQueue;

static NSString *SURemoteServiceLookupReason = @"Remote Service Connection";

@interface SURemoteMessagePort ()

@property (nonatomic, copy) NSString *serviceName;
@property (nonatomic) CFMessagePortRef messagePort;
@property (nonatomic, copy) void (^invalidationCallback)(void);
@property (nonatomic) BOOL disabledAutomaticTermination;

@end

@implementation SURemoteMessagePort

@synthesize serviceName = _serviceName;
@synthesize messagePort = _messagePort;
@synthesize invalidationCallback = _invalidationCallback;
@synthesize disabledAutomaticTermination = _disabledAutomaticTermination;

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            gMessagePortsTable = [[NSMutableDictionary alloc] init];
            gMessageQueue = dispatch_queue_create("org.sparkle-project.remote-message-port", DISPATCH_QUEUE_SERIAL);
        });
        
        // If we are a XPC service, protect it from being terminated until the invalidation handler is set
        _disabledAutomaticTermination = YES;
        [[NSProcessInfo processInfo] disableAutomaticTermination:SURemoteServiceLookupReason];
    }
    return self;
}

- (instancetype)initWithServiceName:(NSString *)serviceName
{
    self = [self init];
    if (self != nil) {
        _serviceName = [serviceName copy];
    }
    return self;
}

- (void)dealloc
{
    [self enableAutomaticTermination];
}

- (void)enableAutomaticTermination
{
    if (self.disabledAutomaticTermination) {
        [[NSProcessInfo processInfo] enableAutomaticTermination:SURemoteServiceLookupReason];
        self.disabledAutomaticTermination = NO;
    }
}

- (void)connectWithLookupCompletion:(void (^)(BOOL))lookupCompletionHandler
{
    dispatch_async(gMessageQueue, ^{
        NSMutableArray<SURemoteMessagePort *> *existingMessagePorts = [gMessagePortsTable objectForKey:self.serviceName];
        if (existingMessagePorts != nil && existingMessagePorts.count > 0) {
            self.messagePort = existingMessagePorts[0].messagePort;
            
            [existingMessagePorts addObject:self];
            
            lookupCompletionHandler(YES);
        } else {
            CFMessagePortRef messagePort = CFMessagePortCreateRemote(kCFAllocatorDefault, (CFStringRef)self.serviceName);
            if (messagePort == NULL) {
                lookupCompletionHandler(NO);
            } else {
                self.messagePort = messagePort;
                
                NSMutableArray<SURemoteMessagePort *> *newMessagePorts = [[NSMutableArray alloc] init];
                [newMessagePorts addObject:self];
                [gMessagePortsTable setObject:newMessagePorts forKey:self.serviceName];
                
                lookupCompletionHandler(YES);
            }
        }
    });
}

- (void)setInvalidationHandler:(void (^)(void))invalidationHandler
{
    // We can disable automatic termination now because we will be protected by the invalidationHandler (if this is a XPC service)
    [self enableAutomaticTermination];
    
    dispatch_async(gMessageQueue, ^{
        if (self.messagePort != NULL) {
            self.invalidationCallback = [invalidationHandler copy];
            
            // Note: do not add messagePort to dispatch queue or run loop: it will complain that one shouldn't be added for remote ports
            CFMessagePortSetInvalidationCallBack(self.messagePort, messageInvalidationCallback);
        }
    });
}

- (void)sendMessageWithIdentifier:(int32_t)identifier data:(NSData *)data expectingReply:(BOOL)expectingReply completion:(void (^)(BOOL success, NSData * _Nullable replyData))completionHandler
{
    dispatch_async(gMessageQueue, ^{
        SInt32 status = 0;
        NSData *replyData = nil;
        if (self.messagePort != NULL) {
            CFDataRef dataRef = (__bridge CFDataRef)(data);
            CFDataRef dataReceived = NULL;
            status = CFMessagePortSendRequest(self.messagePort, identifier, dataRef, 0.2, 2.0, expectingReply ? kCFRunLoopDefaultMode : NULL, expectingReply ? &dataReceived : NULL);
            if (expectingReply && status == kCFMessagePortSuccess) {
                replyData = (NSData *)CFBridgingRelease(dataReceived);
            }
        } else {
            status = kCFMessagePortIsInvalid;
        }
        completionHandler(status == kCFMessagePortSuccess, replyData);
    });
}

- (void)sendMessageWithIdentifier:(int32_t)identifier data:(NSData *)data reply:(void (^)(BOOL success, NSData * _Nullable replyData))replyHandler
{
    [self sendMessageWithIdentifier:identifier data:data expectingReply:YES completion:replyHandler];
}

- (void)sendMessageWithIdentifier:(int32_t)identifier data:(NSData *)data completion:(void (^)(BOOL success))completionHandler
{
    [self sendMessageWithIdentifier:identifier data:data expectingReply:NO completion:^(BOOL success, NSData * _Nullable __unused replyData) {
        completionHandler(success);
    }];
}

- (void)invalidate
{
    dispatch_async(gMessageQueue, ^{
        self.invalidationCallback = nil;
        
        if (self.messagePort != NULL) {
            NSMutableArray<SURemoteMessagePort *> *messagePorts = [gMessagePortsTable objectForKey:self.serviceName];
            [messagePorts removeObject:self];
            
            if (messagePorts.count == 0) {
                [gMessagePortsTable removeObjectForKey:self.serviceName];
                
                // Removing our callback is a better decision than waiting for it to be called at an unpredictable time later
                CFMessagePortSetInvalidationCallBack(self.messagePort, NULL);
                CFMessagePortInvalidate(self.messagePort);
                CFRelease(self.messagePort);
                self.messagePort = NULL;
            }
        }
    });
}

static void messageInvalidationCallback(CFMessagePortRef messagePort, void * __unused info)
{
    @autoreleasepool {
        NSString *serviceName = [(const NSString *)CFMessagePortGetName(messagePort) copy];
        
        dispatch_async(gMessageQueue, ^{
            if (serviceName != nil) {
                for (SURemoteMessagePort *remoteMessagePort in [gMessagePortsTable objectForKey:serviceName]) {
                    if (remoteMessagePort.invalidationCallback != nil) {
                        remoteMessagePort.invalidationCallback();
                        remoteMessagePort.invalidationCallback = nil;
                    }
                    remoteMessagePort.messagePort = NULL;
                }
                [gMessagePortsTable removeObjectForKey:serviceName];
            }
            
            CFRelease(messagePort);
        });
    }
}

@end
