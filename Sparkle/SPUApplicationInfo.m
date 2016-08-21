//
//  SUApplicationInfo.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUApplicationInfo.h"
#import "SPUBundleIcon.h"

@implementation SPUApplicationInfo

+ (BOOL)isBackgroundApplication:(NSApplication *)application
{
    return (application.activationPolicy == NSApplicationActivationPolicyAccessory);
}

+ (NSArray<NSRunningApplication *> *)runningApplicationsWithBundle:(NSBundle *)bundle
{
    // Resolve symlinks otherwise when we compare file paths, we may not realize two paths that are represented differently are the same
    NSArray<NSString *> *bundlePathComponents = bundle.bundlePath.stringByResolvingSymlinksInPath.pathComponents;
    NSString *bundleIdentifier = bundle.bundleIdentifier;
    
    NSMutableArray<NSRunningApplication *> *matchedRunningApplications = [[NSMutableArray alloc] init];
    
    if (bundleIdentifier != nil && bundlePathComponents != nil) {
        NSArray *runningApplications =
        (bundleIdentifier != nil) ?
        [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier] :
        [[NSWorkspace sharedWorkspace] runningApplications];
        
        for (NSRunningApplication *runningApplication in runningApplications) {
            // Comparing the URLs hasn't worked well for me in practice, so I'm comparing the file paths instead
            NSString *candidatePath = runningApplication.bundleURL.URLByResolvingSymlinksInPath.path;
            if (candidatePath != nil && [candidatePath.pathComponents isEqualToArray:bundlePathComponents]) {
                [matchedRunningApplications addObject:runningApplication];
            }
        }
    }
    
    return [matchedRunningApplications copy];
}

+ (NSRunningApplication *)runningApplicationWithBundle:(NSBundle *)bundle
{
    return [[self runningApplicationsWithBundle:bundle] firstObject];
}

@end
