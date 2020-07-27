//
//  SUBundleIcon.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/24/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUBundleIcon.h"
#import "SUHost.h"


#include "AppKitPrevention.h"

@implementation SUBundleIcon

// Note: To obtain the most current bundle icon file from the Info dictionary, this should take a SUHost, not a NSBundle
+ (NSURL *)iconURLForHost:(SUHost *)host
{
    NSString *resource = [host objectForInfoDictionaryKey:@"CFBundleIconFile"];
    if (resource == nil || ![resource isKindOfClass:[NSString class]]) {
        return nil;
    }
    
    NSURL *iconURL = [host.bundle URLForResource:resource withExtension:@"icns"];
    
    // The resource could already be containing the path extension, so try again without the extra extension
    if (iconURL == nil) {
        iconURL = [host.bundle URLForResource:resource withExtension:nil];
    }
    return iconURL;
}

@end
