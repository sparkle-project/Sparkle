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

+ (void)probeInstallerInProgressForHost:(SUHost *)host completion:(void (^)(BOOL))completionHandler
{
    NSString *hostBundleIdentifier = host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    
    SURemoteMessagePort *remotePort = [[SURemoteMessagePort alloc] initWithServiceName:SUAutoUpdateServiceNameForBundleIdentifier(hostBundleIdentifier)];
    
    [remotePort connectWithLookupCompletion:^(BOOL success) {
        if (success) {
            [remotePort invalidate];
        }
        completionHandler(success);
    } invalidationHandler:^{}];
}

+ (void)probeInstallerUpdateItemForHost:(SUHost *)host completion:(void (^)(SUAppcastItem  * _Nullable))completionHandler
{
    NSString *hostBundleIdentifier = host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    
    SURemoteMessagePort *remotePort = [[SURemoteMessagePort alloc] initWithServiceName:SUAutoUpdateServiceNameForBundleIdentifier(hostBundleIdentifier)];
    
    __block BOOL handledCompletion = NO;
    
    [remotePort connectWithLookupCompletion:^(BOOL lookupSuccess) {
        if (!lookupSuccess) {
            if (!handledCompletion) {
                completionHandler(nil);
                handledCompletion = YES;
            }
        } else {
            [remotePort sendMessageWithIdentifier:SUReceiveUpdateAppcastItemData data:[NSData data] reply:^(BOOL success, NSData * _Nullable replyData) {
                [remotePort invalidate];
                
                if (!handledCompletion) {
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
                }
                handledCompletion = YES;
            }];
        }
    } invalidationHandler:^{
        if (!handledCompletion) {
            completionHandler(nil);
            handledCompletion = YES;
        }
    }];
}

@end
