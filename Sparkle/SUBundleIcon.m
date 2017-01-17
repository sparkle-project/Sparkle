//
//  SUBundleIcon.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/24/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUBundleIcon.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@implementation SUBundleIcon

+ (NSURL *)iconURLForBundle:(NSBundle *)bundle
{
    NSString *resource = [bundle objectForInfoDictionaryKey:@"CFBundleIconFile"];
    if (resource == nil || ![resource isKindOfClass:[NSString class]]) {
        return nil;
    }
    
    NSURL *iconURL = [bundle URLForResource:resource withExtension:@"icns"];
    
    // The resource could already be containing the path extension, so try again without the extra extension
    if (iconURL == nil) {
        iconURL = [bundle URLForResource:resource withExtension:nil];
    }
    return iconURL;
}

@end
