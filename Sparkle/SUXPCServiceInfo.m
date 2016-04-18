//
//  SUXPCServiceInfo.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUXPCServiceInfo.h"

BOOL SUXPCServiceExists(NSString *bundleName)
{
    NSURL *xpcBundleURL = SUXPCServiceURL(bundleName);
    return (xpcBundleURL != nil && [xpcBundleURL checkResourceIsReachableAndReturnError:NULL]);
}

NSURL * _Nullable SUXPCServiceURL(NSString *bundleName)
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSURL *executableURL = mainBundle.executableURL;
    if (executableURL == nil) {
        return nil;
    }
    
    NSURL *xpcBundleURL = [[[executableURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"XPCServices"] URLByAppendingPathComponent:bundleName] URLByAppendingPathExtension:@"xpc"];
    
    return xpcBundleURL;
}
