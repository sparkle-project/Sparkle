//
//  SPUApplicationIcon.m
//  Sparkle
//
//  Created by Mayur Pawashe on 8/20/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUApplicationIcon.h"
#import "SPUBundleIcon.h"

@implementation SPUApplicationIcon

+ (NSImage *)bestIconForBundle:(NSBundle *)bundle
{
    NSURL *iconURL = [SPUBundleIcon iconURLForBundle:bundle];
    
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

@end
