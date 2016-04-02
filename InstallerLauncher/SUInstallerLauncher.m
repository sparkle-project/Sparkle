//
//  SUInstallerLauncher.m
//  InstallerLauncher
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUInstallerLauncher.h"
#import "SUFileManager.h"
#import "SULog.h"
#import <AppKit/AppKit.h>

@implementation SUInstallerLauncher

- (void)launchInstallerAtPath:(NSString *)installerPath withArguments:(NSArray *)arguments completion:(void (^)(BOOL success))completionHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *quarantineError = nil;
        SUFileManager *fileManager = [SUFileManager fileManagerAllowingAuthorization:NO];
        
        if (![fileManager releaseItemFromQuarantineAtRootURL:[NSURL fileURLWithPath:installerPath] error:&quarantineError]) {
            // This may or may not be a fatal error depending on if the process is sandboxed or not
            SULog(@"Failed to release quarantine on installer at %@ with error %@", installerPath, quarantineError);
        }
        
        NSError *launchError = nil;
        NSRunningApplication *runningApplication = [[NSWorkspace sharedWorkspace] launchApplicationAtURL:[NSURL fileURLWithPath:installerPath] options:(NSWorkspaceLaunchOptions)(NSWorkspaceLaunchDefault | NSWorkspaceLaunchNewInstance) configuration:@{NSWorkspaceLaunchConfigurationArguments : arguments} error:&launchError];
        
        if (runningApplication == nil) {
            SULog(@"Failed to launch AutoUpdate app with error: %@", launchError);
        }
        
        completionHandler(runningApplication != nil);
    });
}

- (void)testWritabilityAtPath:(NSString *)path completion:(void (^)(BOOL isWritable))completionHandler
{
    completionHandler([[NSFileManager defaultManager] isWritableFileAtPath:path]);
}

@end
