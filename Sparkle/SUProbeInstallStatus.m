//
//  SUProbeInstallStatus.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/20/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUProbeInstallStatus.h"
#import "SULocalMessagePort.h"
#import "SURemoteMessagePort.h"
#import "SUXPCRemoteMessagePort.h"
#import "SUXPCServiceInfo.h"
#import "SURemoteMessagePortProtocol.h"
#import "SUHost.h"
#import "SUMessageTypes.h"
#import "SUInstallationInfo.h"
#import "SUSecureCoding.h"

@implementation SUProbeInstallStatus

+ (void)probeInstallerInProgressForHost:(SUHost *)host completion:(void (^)(BOOL))completionHandler
{
    NSString *hostBundleIdentifier = host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    
    id <SURemoteMessagePortProtocol> remotePort = nil;
    NSString *serviceName = SUAutoUpdateServiceNameForBundleIdentifier(hostBundleIdentifier);
    if (!SUXPCServiceExists(@REMOTE_MESSAGE_PORT_PRODUCT_NAME)) {
        remotePort = [[SURemoteMessagePort alloc] initWithServiceName:serviceName];
    } else {
        remotePort = [[SUXPCRemoteMessagePort alloc] initWithServiceName:serviceName];
    }
    
    [remotePort connectWithLookupCompletion:^(BOOL success) {
        if (success) {
            [remotePort invalidate];
        }
        completionHandler(success);
    }];
}

+ (void)probeInstallerUpdateItemForHost:(SUHost *)host completion:(void (^)(SUInstallationInfo  * _Nullable))completionHandler
{
    NSString *hostBundleIdentifier = host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    
    id <SURemoteMessagePortProtocol> remotePort = nil;
    NSString *serviceName = SUAutoUpdateServiceNameForBundleIdentifier(hostBundleIdentifier);
    if (!SUXPCServiceExists(@REMOTE_MESSAGE_PORT_PRODUCT_NAME)) {
        remotePort = [[SURemoteMessagePort alloc] initWithServiceName:serviceName];
    } else {
        remotePort = [[SUXPCRemoteMessagePort alloc] initWithServiceName:serviceName];
    }
    
    [remotePort connectWithLookupCompletion:^(BOOL lookupSuccess) {
        if (!lookupSuccess) {
            completionHandler(nil);
        } else {
            [remotePort sendMessageWithIdentifier:SUReceiveUpdateAppcastItemData data:[NSData data] reply:^(BOOL success, NSData * _Nullable replyData) {
                [remotePort invalidate];
                
                if (!success || replyData == nil) {
                    completionHandler(nil);
                } else {
                    NSData *nonNullReplyData = replyData;
                    SUInstallationInfo *installationInfo = (SUInstallationInfo *)SUUnarchiveRootObjectSecurely(nonNullReplyData, [SUInstallationInfo class]);
                    
                    if (installationInfo != nil) {
                        completionHandler(installationInfo);
                    } else {
                        completionHandler(nil);
                    }
                }
            }];
        }
    }];
}

@end
