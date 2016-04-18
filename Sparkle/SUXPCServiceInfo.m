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
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSURL *executableURL = mainBundle.executableURL;
    if (executableURL == nil) {
        return NO;
    }
    
    NSURL *xpcBundleURL = [[[executableURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"XPCServices"] URLByAppendingPathComponent:bundleName] URLByAppendingPathExtension:@"xpc"];
    
    BOOL serviceExists = [xpcBundleURL checkResourceIsReachableAndReturnError:NULL];
    return serviceExists;
}
