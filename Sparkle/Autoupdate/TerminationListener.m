//
//  TerminationListener.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/7/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "TerminationListener.h"
#import "SULog.h"

#include <sys/types.h>
#include <sys/event.h>
#include <sys/time.h>

#ifdef _APPKITDEFINES_H
#error This is class should NOT import AppKit
#endif

@interface TerminationListener ()

@property (nonatomic, readonly, nullable) NSNumber *processIdentifier;
@property (nonatomic) BOOL watchedTermination;
@property (nonatomic, copy) void (^completionBlock)(BOOL);

@end

@implementation TerminationListener

@synthesize completionBlock = _completionBlock;
@synthesize processIdentifier = _processIdentifier;
@synthesize watchedTermination = _watchedTermination;

- (instancetype)initWithProcessIdentifier:(NSNumber * _Nullable)processIdentifier
{
    self = [super init];
    if (self != nil) {
        _processIdentifier = processIdentifier;
    }
    
    return self;
}

- (BOOL)terminated
{
    return (self.watchedTermination || self.processIdentifier == nil) ? YES : (kill(self.processIdentifier.intValue, 0) != 0);
}

- (void)invokeCompletionWithSuccess:(BOOL)success
{
    self.completionBlock(success);
    self.completionBlock = nil;
}

- (void)startListeningWithCompletion:(void (^)(BOOL))completionBlock
{
    self.completionBlock = completionBlock;
    
    if (self.processIdentifier == nil) {
        [self invokeCompletionWithSuccess:YES];
        return;
    }
    
    // Use kqueues to determine when the process will terminate
    // As described in https://developer.apple.com/library/mac/technotes/tn2050/_index.html#//apple_ref/doc/uid/DTS10003081-CH1-SUBSECTION10
    // By using kqueues, we can stay away from using AppKit in case we ever decide to abandon it
    
    pid_t processIdentifier = self.processIdentifier.intValue;
    int queue = kqueue();
    if (queue == -1) {
        SULog(@"Failed to create kqueue() due to error %d: %@", errno, @(strerror(errno)));
        [self invokeCompletionWithSuccess:NO];
        return;
    }
    
    struct kevent changes;
    EV_SET(&changes, processIdentifier, EVFILT_PROC, EV_ADD | EV_RECEIPT, NOTE_EXIT, 0, NULL);
    
    if (kevent(queue, &changes, 1, &changes, 1, NULL) == -1) {
        SULog(@"Failed to invoke kevent() due to error %d: %@", errno, @(strerror(errno)));
        [self invokeCompletionWithSuccess:NO];
        return;
    }
    
    // We will assume this terminationListener will never be deallocated
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wcast-qual"
    CFFileDescriptorContext context = { 0, (void *)CFBridgingRetain(self), NULL, NULL, NULL };
#pragma clang diagnostic pop
    CFFileDescriptorRef noteExitKQueueRef = CFFileDescriptorCreate(NULL, queue, true, noteExitKQueueCallback, &context);
    if (noteExitKQueueRef == NULL) {
        SULog(@"Failed to create file descriptor via CFFileDescriptorCreate()");
        CFRelease((__bridge CFTypeRef)(self));
        [self invokeCompletionWithSuccess:NO];
        return;
    }
    
    CFRunLoopSourceRef runLoopSource = CFFileDescriptorCreateRunLoopSource(NULL, noteExitKQueueRef, 0);
    if (runLoopSource == NULL) {
        SULog(@"Failed to create runLoopSource via CFFileDescriptorCreateRunLoopSource()");
        CFRelease((__bridge CFTypeRef)(self));
        [self invokeCompletionWithSuccess:NO];
        return;
    }
    
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopDefaultMode);
    CFRelease(runLoopSource);
    
    CFFileDescriptorEnableCallBacks(noteExitKQueueRef, kCFFileDescriptorReadCallBack);
}

static void noteExitKQueueCallback(CFFileDescriptorRef file, CFOptionFlags __unused callBackTypes, void *info)
{
    struct kevent event;
    kevent(CFFileDescriptorGetNativeDescriptor(file), NULL, 0, &event, 1, NULL);
    
    TerminationListener *self = CFBridgingRelease(info);
    self.watchedTermination = YES;
    [self invokeCompletionWithSuccess:YES];
}

@end
