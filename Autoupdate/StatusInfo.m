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

@interface StatusInfo () <NSXPCListenerDelegate>

@property (nonatomic) NSXPCListener *xpcListener;

@end

@implementation StatusInfo

@synthesize xpcListener = _xpcListener;
@synthesize installationInfoData = _installationInfoData;

- (instancetype)initWithHostBundleIdentifier:(NSString *)bundleIdentifier
{
    self = [super init];
    if (self != nil) {
        _xpcListener = [[NSXPCListener alloc] initWithMachServiceName:SPUStatusInfoServiceNameForBundleIdentifier(bundleIdentifier)];
        _xpcListener.delegate = self;
    }
    return self;
}

- (void)startListener
{
    [self.xpcListener resume];
}

- (void)invalidate
{
    [self.xpcListener invalidate];
    self.xpcListener = nil;
}

- (BOOL)listener:(NSXPCListener *)__unused listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection
{
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUStatusInfoProtocol)];
    newConnection.exportedObject = self;
    
    [newConnection resume];
    
    return YES;
}

- (void)probeStatusInfoWithReply:(void (^)(NSData * _Nullable))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        reply(self.installationInfoData);
    });
}

- (void)probeStatusConnectivityWithReply:(void (^)(void))reply
{
    reply();
}

@end
