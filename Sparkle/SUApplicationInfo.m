//
//  SUApplicationInfo.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUApplicationInfo.h"
#import "SUBundleIcon.h"

@implementation SUApplicationInfo

+ (BOOL)isBackgroundApplication:(NSApplication *)application
{
    return (application.activationPolicy == NSApplicationActivationPolicyAccessory);
}

+ (NSImage *)bestIconForBundle:(NSBundle *)bundle
{
    NSURL *iconURL = [SUBundleIcon iconURLForBundle:bundle];
    
    NSImage *icon = (iconURL == nil) ? nil : [[NSImage alloc] initWithContentsOfURL:iconURL];
    // Use a default icon if none is defined.
    if (!icon) {
        // this asumption may not be correct (eg. even though we're not the main bundle, it could be still be a regular app)
        // but still better than nothing if no icon was included
        BOOL isMainBundle = (bundle == [NSBundle mainBundle]);
        
        NSString *fileType = isMainBundle ? (__bridge NSString *)kUTTypeApplication : (__bridge NSString *)kUTTypeBundle;
        icon = [[NSWorkspace sharedWorkspace] iconForFileType:fileType];
    }
    return icon;
}

+ (NSRunningApplication *)runningApplicationWithBundle:(NSBundle *)bundle
{
    NSString *bundlePath = bundle.bundlePath;
    NSString *bundleIdentifier = bundle.bundleIdentifier;
    
    if (bundleIdentifier != nil && bundlePath != nil) {
        NSArray *runningApplications =
        (bundleIdentifier != nil) ?
        [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier] :
        [[NSWorkspace sharedWorkspace] runningApplications];
        
        for (NSRunningApplication *runningApplication in runningApplications) {
            // Comparing the URLs hasn't worked well for me in practice, so I'm comparing the file paths instead
            NSString *candidatePath = runningApplication.bundleURL.path;
            if (candidatePath != nil && [candidatePath isEqualToString:bundlePath]) {
                return runningApplication;
            }
        }
    }
    return nil;
}

@end
