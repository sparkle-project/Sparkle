//
//  SUUpdaterPermission.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUpdaterPermission.h"
#import "SUInstallerLauncherProtocol.h"

@interface SUUpdaterPermission ()

@property (nonatomic) BOOL allowsPermission;
@property (nonatomic) BOOL checkedPermission;

@end

@implementation SUUpdaterPermission

@synthesize allowsPermission = _allowsPermission;
@synthesize checkedPermission = _checkedPermission;

- (void)testUpdateWritabilityAtPath:(NSString *)path completion:(void (^)(BOOL))completionHandler
{
    if (!self.checkedPermission) {
        NSXPCConnection *launcherConnection = [[NSXPCConnection alloc] initWithServiceName:@"org.sparkle-project.InstallerLauncher"];
        launcherConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerLauncherProtocol)];
        [launcherConnection resume];
        
        __weak SUUpdaterPermission *weakSelf = self;
        [launcherConnection.remoteObjectProxy testWritabilityAtPath:path completion:^(BOOL isWritable) {
            [launcherConnection invalidate];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                weakSelf.checkedPermission = YES;
                weakSelf.allowsPermission = isWritable;
                completionHandler(isWritable);
            });
        }];
    } else {
        completionHandler(self.allowsPermission);
    }
}

@end
