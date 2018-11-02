//
//  SUXPCServiceInfo.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUXPCServiceInfo.h"


#include "AppKitPrevention.h"

BOOL SPUXPCServiceExists(NSString *bundleName)
{
    NSBundle *xpcBundle = SPUXPCServiceBundle(bundleName);
    if (xpcBundle == nil) {
        return NO;
    }
    
    NSString *version = [xpcBundle objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey];
    NSString *projectVersion = @""CURRENT_PROJECT_VERSION;
    if (version == nil || ![version isEqualToString:projectVersion]) {
        // Use NSLog instead of SULog here because this is a developer configuration error...
        NSLog(@"Error: XPC Version mismatch. Framework version is %@ but XPC Service (%@) version is %@", projectVersion, xpcBundle.bundlePath, version);
        NSLog(@"Not using XPC Service...");
        return NO;
    }
    
    return YES;
}

NSBundle * _Nullable SPUXPCServiceBundle(NSString *bundleName)
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSURL *executableURL = mainBundle.executableURL;
    if (executableURL == nil) {
        return nil;
    }
    
    NSURL *xpcBundleURL = [[[executableURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"XPCServices"] URLByAppendingPathComponent:bundleName] URLByAppendingPathExtension:@"xpc"];
    
    return [NSBundle bundleWithURL:xpcBundleURL];
}
