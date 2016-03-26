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
#import "SUHost.h"
#import "SUMessageTypes.h"
#import "SUAppcastItem.h"
#import "SUSecureCoding.h"

@implementation SUProbeInstallStatus

+ (BOOL)probeInstallerInProgressForHost:(SUHost *)host
{
    NSString *hostBundleIdentifier = host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    
    SURemoteMessagePort *remotePort = [[SURemoteMessagePort alloc] initWithServiceName:SUAutoUpdateServiceNameForBundleIdentifier(hostBundleIdentifier) invalidationCallback:^{}];
    [remotePort invalidate];
    return (remotePort != nil);
}

+ (void)probeInstallerUpdateItemForHost:(SUHost *)host completion:(void (^)(SUAppcastItem  * _Nullable))completionHandler
{
    NSString *hostBundleIdentifier = host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    
    SURemoteMessagePort *remotePort = [[SURemoteMessagePort alloc] initWithServiceName:SUAutoUpdateServiceNameForBundleIdentifier(hostBundleIdentifier) invalidationCallback:^{}];
    if (remotePort == nil) {
        completionHandler(nil);
        return;
    }
    
    [remotePort sendMessageWithIdentifier:SUReceiveUpdateAppcastItemData data:[NSData data] reply:^(BOOL success, NSData * _Nullable replyData) {
        if (!success || replyData == nil) {
            completionHandler(nil);
        } else {
            NSData *nonNullReplyData = replyData;
            SUAppcastItem  * _Nullable updateItem = SUUnarchiveRootObjectSecurely(nonNullReplyData, [SUAppcastItem class]);
            
            if (updateItem != nil) {
                completionHandler(updateItem);
            } else {
                completionHandler(nil);
            }
        }
        [remotePort invalidate];
    }];
}

@end
