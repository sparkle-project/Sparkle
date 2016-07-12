//
//  SUProbeInstallStatus.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/20/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUProbeInstallStatus.h"
#import "SUXPCServiceInfo.h"
#import "SUHost.h"
#import "SUMessageTypes.h"
#import "SUInstallationInfo.h"
#import "SUSecureCoding.h"
#import "SUInstallerStatus.h"
#import "SUXPCInstallerStatus.h"
#import "SULog.h"

// This timeout is if probing the installer takes too long
// It should be at least more than 1 second since a probe can take around that much time
#define PROBE_TIMEOUT 7

@implementation SUProbeInstallStatus

+ (void)probeInstallerInProgressForHost:(SUHost *)host completion:(void (^)(BOOL))completionHandler
{
    NSString *hostBundleIdentifier = host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    
    id<SUInstallerStatusProtocol> installerStatus = nil;
    if (!SUXPCServiceExists(@INSTALLER_STATUS_PRODUCT_NAME)) {
        installerStatus = [[SUInstallerStatus alloc] init];
    } else {
        installerStatus = [[SUXPCInstallerStatus alloc] init];
    }
    
    __block BOOL handledCompletion = NO;
    
    [installerStatus setInvalidationHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!handledCompletion) {
                completionHandler(NO);
                handledCompletion = YES;
            }
        });
    }];
    
    NSString *serviceName = SUStatusInfoServiceNameForBundleIdentifier(hostBundleIdentifier);
    [installerStatus setServiceName:serviceName];
    
    [installerStatus probeStatusConnectivityWithReply:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!handledCompletion) {
                completionHandler(YES);
                handledCompletion = YES;
            }
        });
        [installerStatus invalidate];
    }];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PROBE_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!handledCompletion) {
            SULog(@"Timed out while probing installer progress");
            completionHandler(NO);
            handledCompletion = YES;
        }
        [installerStatus invalidate];
    });
}

+ (void)probeInstallerUpdateItemForHost:(SUHost *)host completion:(void (^)(SUInstallationInfo  * _Nullable))completionHandler
{
    NSString *hostBundleIdentifier = host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    
    id<SUInstallerStatusProtocol> installerStatus = nil;
    if (!SUXPCServiceExists(@INSTALLER_STATUS_PRODUCT_NAME)) {
        installerStatus = [[SUInstallerStatus alloc] init];
    } else {
        installerStatus = [[SUXPCInstallerStatus alloc] init];
    }
    
    __block BOOL handledCompletion = NO;
    
    [installerStatus setInvalidationHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!handledCompletion) {
                completionHandler(nil);
                handledCompletion = YES;
            }
        });
    }];
    
    NSString *serviceName = SUStatusInfoServiceNameForBundleIdentifier(hostBundleIdentifier);
    [installerStatus setServiceName:serviceName];
    
    [installerStatus probeStatusInfoWithReply:^(NSData * _Nullable installationInfoData) {
        SUInstallationInfo *installationInfo = nil;
        if (installationInfoData != nil) {
            installationInfo = (SUInstallationInfo *)SUUnarchiveRootObjectSecurely((NSData * _Nonnull)installationInfoData, [SUInstallationInfo class]);
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!handledCompletion) {
                completionHandler(installationInfo);
                handledCompletion = YES;
            }
        });
        
        [installerStatus invalidate];
    }];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(PROBE_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!handledCompletion) {
            SULog(@"Timed out while probing installer info data");
            completionHandler(nil);
            handledCompletion = YES;
        }
        [installerStatus invalidate];
    });
}

@end
