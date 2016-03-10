//
//  SURemoteMessagePort.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/9/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SURemoteMessagePort.h"
#import <objc/runtime.h>

@interface SURemoteMessagePort ()

@property (nonatomic) CFMessagePortRef messagePort;
@property (nonatomic, copy) void (^invalidationCallback)(void);

@end

@implementation SURemoteMessagePort

static const char *SURemoteMessagePortSelfKey = "su_messagePort";

@synthesize messagePort = _messagePort;
@synthesize invalidationCallback = _invalidationCallback;

- (nullable instancetype)initWithServiceName:(NSString *)serviceName invalidationCallback:(void (^)(void))invalidationCallback
{
    self = [super init];
    if (self != nil) {
        CFMessagePortRef messagePort = CFMessagePortCreateRemote(kCFAllocatorDefault, (CFStringRef)serviceName);
        if (messagePort == NULL) {
            return nil;
        }
        
        _messagePort = messagePort;
        _invalidationCallback = [invalidationCallback copy];
        
        // We have to set an associated object here because we can't pass an info context to remote message ports when setting up an invalidation handler
        objc_setAssociatedObject((__bridge id)messagePort, SURemoteMessagePortSelfKey, self, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        // Note: do not add messagePort to dispatch queue or run loop: it will complain that one shouldn't be added for remote ports
        CFMessagePortSetInvalidationCallBack(messagePort, messageInvalidationCallback);
    }
    return self;
}

- (BOOL)sendMessageWithIdentifier:(int32_t)identifier data:(NSData *)data
{
    @synchronized(self) {
        SInt32 status = 0;
        if (self.messagePort != NULL) {
            status = CFMessagePortSendRequest(self.messagePort, identifier, (CFDataRef)data, 0.1, 0.0, NULL, NULL);
        } else {
            status = kCFMessagePortIsInvalid;
        }
        return (status == kCFMessagePortSuccess);
    }
}

- (void)invalidate
{
    @synchronized(self) {
        if (self.invalidationCallback != nil) {
            self.invalidationCallback = nil;
            CFMessagePortInvalidate(self.messagePort);
        }
    }
}

- (void)dealloc
{
    [self invalidate];
}

// For safetly, let's not assume what thread this may be called on
static void messageInvalidationCallback(CFMessagePortRef messagePort, void * __unused info)
{
    SURemoteMessagePort *self = objc_getAssociatedObject((__bridge id)(messagePort), SURemoteMessagePortSelfKey);
    
    @synchronized(self) {
        if (self.invalidationCallback != nil) {
            self.invalidationCallback();
            self.invalidationCallback = nil;
        }
        
        self.messagePort = NULL;
    }
    
    objc_setAssociatedObject((__bridge id)(messagePort), SURemoteMessagePortSelfKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    CFRelease(messagePort);
}

@end
