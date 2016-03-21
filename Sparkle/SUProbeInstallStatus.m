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

@implementation SUProbeInstallStatus

+ (BOOL)probeInstallerInProgressForHost:(SUHost *)host
{
    SURemoteMessagePort *remotePort = [[SURemoteMessagePort alloc] initWithServiceName:SUAutoUpdateServiceNameForHost(host) invalidationCallback:^{}];
    [remotePort invalidate];
    return (remotePort != nil);
}

+ (void)probeInstallerUpdateItemForHost:(SUHost *)host completion:(void (^)(SUAppcastItem  * _Nullable))completionHandler
{
    SURemoteMessagePort *remotePort = [[SURemoteMessagePort alloc] initWithServiceName:SUAutoUpdateServiceNameForHost(host) invalidationCallback:^{}];
    if (remotePort == nil) {
        completionHandler(nil);
        return;
    }
    
    [remotePort sendMessageWithIdentifier:SUReceiveUpdateAppcastItemData data:[NSData data] reply:^(BOOL success, NSData * _Nullable replyData) {
        if (!success || replyData == nil) {
            completionHandler(nil);
        } else {
            NSData *nonNullReplyData = replyData;
            
            // This boilerplate is the only way I've found to decode a class securely
            NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:nonNullReplyData];
            unarchiver.requiresSecureCoding = YES;
            SUAppcastItem *updateItem = [unarchiver decodeObjectOfClass:[SUAppcastItem class] forKey:SUAppcastItemArchiveKey];
            [unarchiver finishDecoding];
            
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
