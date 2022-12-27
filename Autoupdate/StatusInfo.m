//
//  StatusInfo.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "StatusInfo.h"
#import "SPUMessageTypes.h"


#include "AppKitPrevention.h"

#define REPLY_STATUS_INFO_TIMEOUT 2

@interface StatusInfo () <NSXPCListenerDelegate>
@end

@implementation StatusInfo
{
    NSXPCListener *_xpcListener;
    NSMutableDictionary *_pendingReplies;
    
    NSUInteger _pendingReplyCounter;
}

@synthesize installationInfoData = _installationInfoData;

- (instancetype)initWithHostBundleIdentifier:(NSString *)bundleIdentifier
{
    self = [super init];
    if (self != nil) {
        _xpcListener = [[NSXPCListener alloc] initWithMachServiceName:SPUStatusInfoServiceNameForBundleIdentifier(bundleIdentifier)];
        _xpcListener.delegate = self;
        _pendingReplies = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)startListener
{
    [_xpcListener resume];
}

- (void)invalidate
{
    [_xpcListener invalidate];
    _xpcListener = nil;
}

- (BOOL)listener:(NSXPCListener *)__unused listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection
{
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUStatusInfoProtocol)];
    newConnection.exportedObject = self;
    
    [newConnection resume];
    
    return YES;
}

- (void)setInstallationInfoData:(NSData *)installationInfoData
{
    _installationInfoData = installationInfoData;
    
    // Respond to all of our pending replies
    for (NSNumber *replyKey in _pendingReplies) {
        void (^replyBlock)(NSData * _Nullable) = self->_pendingReplies[replyKey];
        replyBlock(_installationInfoData);
    }
    
    [_pendingReplies removeAllObjects];
}

- (void)probeStatusInfoWithReply:(void (^)(NSData * _Nullable))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_installationInfoData != nil) {
            reply(self->_installationInfoData);
        } else {
            // If we don't have the installation info data currently, we may receive it in a very short window afterwards
            // In this case wait a bit for the reply. If we receive the data it will be in -setInstallationInfoData:
            NSUInteger currentReplyCounter = self->_pendingReplyCounter;
            self->_pendingReplyCounter++;

            NSNumber *currentReplyCounterKey = @(currentReplyCounter);
            self->_pendingReplies[currentReplyCounterKey] = [reply copy];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(REPLY_STATUS_INFO_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                void (^replyBlock)(NSData * _Nullable) = self->_pendingReplies[currentReplyCounterKey];
                if (replyBlock != nil) {
                    replyBlock(self->_installationInfoData);
                    [self->_pendingReplies removeObjectForKey:currentReplyCounterKey];
                }
            });
        }
    });
}

- (void)probeStatusConnectivityWithReply:(void (^)(void))reply
{
    reply();
}

@end
