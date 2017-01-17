//
//  SUSystemUpdateInfo.m
//  Sparkle
//
//  Created by Mayur Pawashe on 12/23/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUSystemUpdateInfo.h"
#import "SUHost.h"
#import "SUConstants.h"
#import "SUFileManager.h"


#include "AppKitPrevention.h"

@implementation SUSystemUpdateInfo

+ (BOOL)systemAllowsAutomaticUpdatesForHost:(SUHost *)host
{
    // Does the developer want us to disable automatic updates?
    NSNumber *developerAllowsAutomaticUpdates = [host objectForInfoDictionaryKey:SUAllowsAutomaticUpdatesKey];
    if (developerAllowsAutomaticUpdates != nil && !developerAllowsAutomaticUpdates.boolValue) {
        return NO;
    }
    
    // Can we automatically update in the background without bugging the user (e.g, with a administrator password prompt)?
    // Note it's very well possible to have the bundle be writable but not be able to write into the parent directory
    // And if the bundle isn't writable, but we can write into the parent directory, we will still need to authorize to replace it
    NSString *bundlePath = [host bundlePath];
    if (![[NSFileManager defaultManager] isWritableFileAtPath:bundlePath.stringByDeletingLastPathComponent] || ![[NSFileManager defaultManager] isWritableFileAtPath:bundlePath]) {
        return NO;
    }
    
    // Just because we have writability access does not mean we can set the correct owner/group silently
    // Test if we can set the owner/group on a temporarily created file
    // If we can, then we can probably perform an update without authorization
    // One place where this matters is if you copy and run an app from /tmp/
    
    NSString *tempFilename = @"permission_test" ;
    
    SUFileManager *suFileManager = [SUFileManager defaultManager];
    NSURL *tempDirectoryURL = [suFileManager makeTemporaryDirectoryWithPreferredName:tempFilename appropriateForDirectoryURL:[NSURL fileURLWithPath:NSTemporaryDirectory()] error:NULL];
    
    if (tempDirectoryURL == nil) {
        // I don't imagine this ever happening but in case it does, requesting authorization may be the better option
        return NO;
    }
    
    NSURL *tempFileURL = [tempDirectoryURL URLByAppendingPathComponent:tempFilename];
    
    BOOL changeOwnerAndGroupSuccess =
    [[NSData data] writeToURL:tempFileURL atomically:NO] &&
    [suFileManager changeOwnerAndGroupOfItemAtRootURL:tempFileURL toMatchURL:host.bundle.bundleURL error:NULL];
    
    [suFileManager removeItemAtURL:tempDirectoryURL error:NULL];
    
    return changeOwnerAndGroupSuccess;
}

@end
