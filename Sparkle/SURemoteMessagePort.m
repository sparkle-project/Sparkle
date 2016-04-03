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

@interface SURemoteMessagePort ()

@property (nonatomic, copy) NSString *serviceName;
@property (nonatomic) CFMessagePortRef messagePort;
@property (nonatomic, copy) void (^invalidationHandler)(void);

@end

@implementation SURemoteMessagePort

@synthesize serviceName = _serviceName;
@synthesize messagePort = _messagePort;
@synthesize invalidationHandler = _invalidationHandler;

- (instancetype)initWithServiceName:(NSString *)serviceName
{
    self = [super init];
    if (self != nil) {
        _serviceName = [serviceName copy];
        
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            gMessagePortsTable = [[NSMutableDictionary alloc] init];
            gMessageQueue = dispatch_queue_create("org.sparkle-project.remote-message-port", DISPATCH_QUEUE_SERIAL);
        });
    }
    return self;
}

- (void)connectWithLookupCompletion:(void (^)(BOOL))lookupCompletionHandler invalidationHandler:(void (^)(void))invalidationHandler
{
    dispatch_async(gMessageQueue, ^{
        NSMutableArray<SURemoteMessagePort *> *existingMessagePorts = [gMessagePortsTable objectForKey:self.serviceName];
        if (existingMessagePorts != nil && existingMessagePorts.count > 0) {
            self.messagePort = existingMessagePorts[0].messagePort;
            self.invalidationHandler = [invalidationHandler copy];
            
            [existingMessagePorts addObject:self];
            
            lookupCompletionHandler(YES);
        } else {
            CFMessagePortRef messagePort = CFMessagePortCreateRemote(kCFAllocatorDefault, (CFStringRef)self.serviceName);
            if (messagePort == NULL) {
                lookupCompletionHandler(NO);
            } else {
                self.messagePort = messagePort;
                self.invalidationHandler = [invalidationHandler copy];
                
                NSMutableArray<SURemoteMessagePort *> *newMessagePorts = [[NSMutableArray alloc] init];
                [newMessagePorts addObject:self];
                [gMessagePortsTable setObject:newMessagePorts forKey:self.serviceName];
                
                // Note: do not add messagePort to dispatch queue or run loop: it will complain that one shouldn't be added for remote ports
                CFMessagePortSetInvalidationCallBack(messagePort, messageInvalidationCallback);
                
                lookupCompletionHandler(YES);
            }
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
        self.invalidationHandler = nil;
        
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
                    if (remoteMessagePort.invalidationHandler != nil) {
                        remoteMessagePort.invalidationHandler();
                        remoteMessagePort.invalidationHandler = nil;
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
