//
//  SURemoteMessagePort.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/9/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SURemoteMessagePort.h"
#import <objc/runtime.h>

// The global message queue where we perform message port operations
// We want this to be global across live remote ports, otherwise I fear for out-of-order invalidation events and the such
static dispatch_queue_t gMessageQueue;

@interface SURemoteMessagePort ()

@property (nonatomic, copy) NSString *serviceName;
@property (nonatomic) CFMessagePortRef messagePort;
@property (nonatomic, copy) void (^invalidationHandler)(void);

@end

@implementation SURemoteMessagePort

static const char *SURemoteMessagePortSelfKey = "su_messagePort";

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
            gMessageQueue = dispatch_queue_create("org.sparkle-project.remote-message-port", DISPATCH_QUEUE_SERIAL);
        });
    }
    return self;
}

- (void)connectWithLookupCompletion:(void (^)(BOOL))lookupCompletionHandler invalidationHandler:(void (^)(void))invalidationHandler
{
    dispatch_async(gMessageQueue, ^{
        CFMessagePortRef messagePort = CFMessagePortCreateRemote(kCFAllocatorDefault, (CFStringRef)self.serviceName);
        if (messagePort == NULL) {
            lookupCompletionHandler(NO);
        } else {
            self.messagePort = messagePort;
            self.invalidationHandler = [invalidationHandler copy];
            
            CFRetain((__bridge CFTypeRef)(self));
            
            // We have to set an associated object here because we can't pass an info context to remote message ports when setting up an invalidation handler
            objc_setAssociatedObject((__bridge id)messagePort, SURemoteMessagePortSelfKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            
            // Note: do not add messagePort to dispatch queue or run loop: it will complain that one shouldn't be added for remote ports
            CFMessagePortSetInvalidationCallBack(messagePort, messageInvalidationCallback);
            
            lookupCompletionHandler(YES);
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
        if (self.invalidationHandler != nil) {
            self.invalidationHandler = nil;
            CFMessagePortInvalidate(self.messagePort);
        }
    });
}

// For safetly, let's not assume what thread this may be called on
static void messageInvalidationCallback(CFMessagePortRef messagePort, void * __unused info)
{
    @autoreleasepool {
        SURemoteMessagePort *self = objc_getAssociatedObject((__bridge id)(messagePort), SURemoteMessagePortSelfKey);
        
        dispatch_async(gMessageQueue, ^{
            if (self.invalidationHandler != nil) {
                self.invalidationHandler();
                self.invalidationHandler = nil;
            }
            
            self.messagePort = NULL;
            
            objc_setAssociatedObject((__bridge id)(messagePort), SURemoteMessagePortSelfKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            CFRelease(messagePort);
            
            CFRelease((__bridge CFTypeRef)(self));
        });
    }
}

@end
