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

- (void)launchInstallerAtPath:(NSString *)installerPath withHostBundleIdentifier:(NSString *)hostBundleIdentifier inheritingPrivileges:(BOOL)inheritingPrivileges completion:(void (^)(BOOL success))completionHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSError *quarantineError = nil;
        SUFileManager *fileManager = [SUFileManager fileManager];
        
        if (![fileManager releaseItemFromQuarantineAtRootURL:[NSURL fileURLWithPath:installerPath] error:&quarantineError]) {
            // This may or may not be a fatal error depending on if the process is sandboxed or not
            SULog(@"Failed to release quarantine on installer at %@ with error %@", installerPath, quarantineError);
        }
        
        NSArray *arguments = @[hostBundleIdentifier, @(inheritingPrivileges).stringValue];
        
        if (!inheritingPrivileges) {
            // This new process does not inherit privileges because it's being launched via LaunchServices
            // This allows the installer app to make authorization requests for example from a non-sandboxed XPC service
            NSError *launchError = nil;
            NSRunningApplication *runningApplication = [[NSWorkspace sharedWorkspace] launchApplicationAtURL:[NSURL fileURLWithPath:installerPath] options:(NSWorkspaceLaunchOptions)(NSWorkspaceLaunchDefault | NSWorkspaceLaunchNewInstance) configuration:@{NSWorkspaceLaunchConfigurationArguments : arguments} error:&launchError];
            
            if (runningApplication == nil) {
                SULog(@"Failed to launch %@ app with error: %@", @SPARKLE_RELAUNCH_TOOL_NAME, launchError);
            }
            
            completionHandler(runningApplication != nil);
        } else {
            // This new process inherits privileges and thus will not use the authorization reference API, nor request a dialog for authorization
            // If we have root permissions, so will this new process
            // The reason I don't create a NSBundle to locate the executable is because I worry about NSBundle caching and if we enter here multiple times
            NSString *executablePath = [[[installerPath stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"MacOS"] stringByAppendingPathComponent:@SPARKLE_RELAUNCH_TOOL_NAME];
            
            NSTask *task = [[NSTask alloc] init];
            task.launchPath = executablePath;
            task.arguments = arguments;
            
            BOOL success = NO;
            @try {
                [task launch];
                success = YES;
            } @catch (NSException *exception) {
                SULog(@"Failed to launch %@ app with exception: %@", @SPARKLE_RELAUNCH_TOOL_NAME, exception);
            }
            
            completionHandler(success);
        }
    });
}

@end
