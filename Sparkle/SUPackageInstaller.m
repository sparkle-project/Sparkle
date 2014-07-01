//
//  SUPackageInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPackageInstaller.h"
#import <Cocoa/Cocoa.h>
#import "SUConstants.h"

@implementation SUPackageInstaller

+ (void)performInstallationToPath:(NSString *)installationPath fromPath:(NSString *)path host:(SUHost *)host delegate:(id<SUInstallerDelegate>)delegate versionComparator:(id<SUVersionComparison>)__unused comparator
{
    // Run installer using the "open" command to ensure it is launched in front of current application.
    // -W = wait until the app has quit.
    // -n = Open another instance if already open.
    // -b = app bundle identifier
    NSString *command = @"/usr/bin/open";
    NSArray *args = @[@"-W", @"-n", @"-b", @"com.apple.installer", path];

    if (![[NSFileManager defaultManager] fileExistsAtPath:command]) {
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUMissingInstallerToolError userInfo:@{ NSLocalizedDescriptionKey: @"Couldn't find Apple's installer tool!" }];
        [self finishInstallationToPath:installationPath withResult:NO host:host error:error delegate:delegate];
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSTask *installer = [NSTask launchedTaskWithLaunchPath:command arguments:args];
        [installer waitUntilExit];

        // Known bug: if the installation fails or is canceled, Sparkle goes ahead and restarts, thinking everything is fine.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishInstallationToPath:installationPath withResult:YES host:host error:nil delegate:delegate];
        });
    });
}

@end
