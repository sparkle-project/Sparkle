//
//  SUUpdaterPermission.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUpdaterPermission.h"
#import "SUInstallerLauncherProtocol.h"

@implementation SUUpdaterPermission

+ (void)testUpdateWritabilityAtPath:(NSString *)path completion:(void (^)(BOOL))completionHandler
{
    NSXPCConnection *launcherConnection = [[NSXPCConnection alloc] initWithServiceName:@"org.sparkle-project.InstallerLauncher"];
    launcherConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerLauncherProtocol)];
    [launcherConnection resume];
    
    [launcherConnection.remoteObjectProxy testWritabilityAtPath:path completion:^(BOOL isWritable) {
        [launcherConnection invalidate];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(isWritable);
        });
    }];
}

@end
