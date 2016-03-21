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
@property (nonatomic, copy) NSData *(^messageCallback)(int32_t, NSData *);
@property (nonatomic, copy) void (^invalidationCallback)(void);
@property (nonatomic, readonly) dispatch_queue_t messageQueue;

@end

@implementation SULocalMessagePort

@synthesize messagePort = _messagePort;
@synthesize messageCallback = _messageCallback;
@synthesize invalidationCallback = _invalidationCallback;
@synthesize messageQueue = _messageQueue;

- (nullable instancetype)initWithServiceName:(NSString *)serviceName messageCallback:(NSData *(^)(int32_t identifier, NSData *data))messageCallback invalidationCallback:(void (^)(void))invalidationCallback
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
        
        _messageQueue = dispatch_queue_create("org.sparkle-project.sparkle-local-port", DISPATCH_QUEUE_SERIAL);
        
        CFMessagePortSetDispatchQueue(messagePort, _messageQueue);
        CFMessagePortSetInvalidationCallBack(messagePort, messageInvalidationCallback);
    }
    return self;
}

- (void)invalidate
{
    dispatch_async(self.messageQueue, ^{
        if (self.invalidationCallback != nil) {
            self.invalidationCallback = nil;
            CFMessagePortInvalidate(self.messagePort);
        }
    });
}

// Called on non-main thread
static CFDataRef messagePortCallback(CFMessagePortRef __unused messagePort, SInt32 messageID, CFDataRef dataRef, void *info)
{
    @autoreleasepool {
        SULocalMessagePort *self = (__bridge SULocalMessagePort *)info;
        // Create a copy that we can safely pass it asynchronously
        // Warning: Do not use a convenience -[NSData copy] or an equivalent call. This crashes, and ASAN will let you know it crashes
        // Most likely because the bytes are set to be freed internally, and not deep copied or something
        NSData *data = [NSData dataWithBytes:CFDataGetBytePtr(dataRef) length:(NSUInteger)CFDataGetLength(dataRef)];
        
        NSData *replyData = nil;
        if (self.messageCallback != nil) {
            replyData = self.messageCallback(messageID, data);
        }
        
        return (CFDataRef)CFBridgingRetain(replyData);
    }
}

// Called on non-main thread
static void messageInvalidationCallback(CFMessagePortRef messagePort, void *info)
{
    @autoreleasepool {
        SULocalMessagePort *self = (__bridge SULocalMessagePort *)info;
        
        dispatch_async(self.messageQueue, ^{
            // note that messageCallback is deallocated on same queue that we're receiving messages from, which is good
            self.messageCallback = nil;
            
            if (self.invalidationCallback != nil) {
                self.invalidationCallback();
                self.invalidationCallback = nil;
            }
            
            self.messagePort = NULL;
            
            CFRelease(messagePort);
            CFRelease((__bridge CFTypeRef)(self));
        });
    }
}

@end
