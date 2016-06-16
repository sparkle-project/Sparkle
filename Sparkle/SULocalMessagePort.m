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
@property (nonatomic, nullable) id<SULocalMessagePortDelegate> delegate;
@property (nonatomic, copy) NSData * _Nullable(^messageHandler)(int32_t, NSData *);
@property (nonatomic, copy) void (^invalidationBlock)(void);
@property (nonatomic, readonly) dispatch_queue_t messageQueue;

@end

@implementation SULocalMessagePort

@synthesize messagePort = _messagePort;
@synthesize delegate = _delegate;
@synthesize messageHandler = _messageHandler;
@synthesize invalidationBlock = _invalidationBlock;
@synthesize messageQueue = _messageQueue;

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        _messageQueue = dispatch_queue_create("org.sparkle-project.sparkle-local-port", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (instancetype)initWithDelegate:(id<SULocalMessagePortDelegate>)delegate
{
    self = [self init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

- (void)setServiceName:(NSString *)serviceName
{
    assert(self.messagePort == NULL);
    
    CFMessagePortContext context = {.version = 0, .info = (void *)CFBridgingRetain(self), .retain = NULL, .release = NULL, .copyDescription = NULL};
    CFMessagePortRef messagePort = CFMessagePortCreateLocal(kCFAllocatorDefault, (CFStringRef)serviceName, messagePortCallback, &context, NULL);
    
    if (messagePort == NULL) {
        CFRelease((__bridge CFTypeRef)(self));
    } else {
        self.messagePort = messagePort;
        CFMessagePortSetDispatchQueue(messagePort, self.messageQueue);
    }
}

- (void)setMessageCallback:(NSData * _Nullable(^)(int32_t identifier, NSData *data))messageCallback
{
    self.messageHandler = messageCallback;
}

- (void)setInvalidationCallback:(void (^)(void))invalidationCallback
{
    if (self.messagePort == NULL) {
        invalidationCallback();
    } else {
        self.invalidationBlock = [invalidationCallback copy];
        CFMessagePortSetInvalidationCallBack(self.messagePort, messageInvalidationCallback);
    }
}

- (void)invalidate
{
    dispatch_async(self.messageQueue, ^{
        if (self.invalidationBlock != nil) {
            self.invalidationBlock = nil;
            CFMessagePortInvalidate(self.messagePort);
        } else {
            [self removeDelegate];
        }
    });
}

- (void)removeDelegate
{
    // Remove our delegate right away but make sure it is released on main thread
    __block id<SULocalMessagePortDelegate> delegate = self.delegate;
    if (delegate != nil) {
        self.delegate = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            delegate = nil;
        });
    }
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
        if (self.delegate != nil) {
            [self.delegate localMessagePortReceivedMessageWithIdentifier:messageID data:data];
        } else if (self.messageHandler != nil) {
            replyData = self.messageHandler(messageID, data);
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
            [self removeDelegate];
            
            // note that messageHandler is deallocated on same queue that we're receiving messages from, which is good
            self.messageHandler = nil;
            
            if (self.invalidationBlock != nil) {
                self.invalidationBlock();
                self.invalidationBlock = nil;
            }
            
            self.messagePort = NULL;
            
            CFRelease(messagePort);
            CFRelease((__bridge CFTypeRef)(self));
        });
    }
}

@end
