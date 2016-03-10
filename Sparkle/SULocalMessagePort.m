//
//  SULocalMessagePort.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/9/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SULocalMessagePort.h"

@interface SULocalMessagePort ()

@property (nonatomic) CFMessagePortRef messagePort;
@property (nonatomic, copy) void (^messageCallback)(int32_t, NSData *);
@property (nonatomic, copy) void (^invalidationCallback)(void);

@end

@implementation SULocalMessagePort

@synthesize messagePort = _messagePort;
@synthesize messageCallback = _messageCallback;
@synthesize invalidationCallback = _invalidationCallback;

- (nullable instancetype)initWithServiceName:(NSString *)serviceName messageCallback:(void (^)(int32_t identifier, NSData *data))messageCallback invalidationCallback:(void (^)(void))invalidationCallback
{
    self = [super init];
    if (self != nil) {
        CFMessagePortContext context = {.version = 0, .info = (void *)CFBridgingRetain(self), .retain = NULL, .release = NULL, .copyDescription = NULL};
        CFMessagePortRef messagePort = CFMessagePortCreateLocal(kCFAllocatorDefault, (CFStringRef)serviceName, messagePortCallback, &context, NULL);
        
        if (messagePort == NULL) {
            CFRelease((__bridge CFTypeRef)(self));
            return nil;
        }
        
        _messagePort = messagePort;
        _messageCallback = [messageCallback copy];
        _invalidationCallback = [invalidationCallback copy];
        
        CFMessagePortSetDispatchQueue(messagePort, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
        CFMessagePortSetInvalidationCallBack(messagePort, messageInvalidationCallback);
    }
    return self;
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

// Called on non-main thread
static CFDataRef messagePortCallback(CFMessagePortRef __unused messagePort, SInt32 messageID, CFDataRef dataRef, void *info)
{
    SULocalMessagePort *self = (__bridge SULocalMessagePort *)info;
    NSData *data = (__bridge NSData *)dataRef;
    
    if (self.messageCallback != nil) {
        self.messageCallback(messageID, data);
    }
    
    // Don't have any use case where I need a reply, for now
    return NULL;
}

// Called on non-main thread
static void messageInvalidationCallback(CFMessagePortRef messagePort, void *info)
{
    SULocalMessagePort *self = (__bridge SULocalMessagePort *)info;
    
    @synchronized(self) {
        // note that messageCallback is deallocated on same queue that we're receiving messages from, which is good
        self.messageCallback = nil;
        
        if (self.invalidationCallback != nil) {
            self.invalidationCallback();
            self.invalidationCallback = nil;
        }
        
        self.messagePort = NULL;
    }
    
    CFRelease(messagePort);
    CFRelease((__bridge CFTypeRef)(self));
}

@end
