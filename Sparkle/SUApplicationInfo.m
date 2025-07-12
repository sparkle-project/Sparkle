//
//  SUApplicationInfo.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS || !BUILDING_SPARKLE

#import "SUApplicationInfo.h"
#import "SUBundleIcon.h"
#import "SUHost.h"
#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@implementation SUApplicationInfo

+ (BOOL)isBackgroundApplication:(NSApplication *)application
{
    return (application.activationPolicy == NSApplicationActivationPolicyAccessory);
}

+ (NSImage *)bestIconForHost:(SUHost *)host
{
    BOOL isMainBundle = [host.bundle isEqualTo:[NSBundle mainBundle]];
 
    // First try NSImageNameApplicationIcon. This image can be dynamically updated if the user's system icon settings change.
    NSImage *icon = isMainBundle ? [NSImage imageNamed:NSImageNameApplicationIcon] : nil;
    
    // Next try asking NSWorkspace for icon of the bundle
    if (icon == nil) {
        icon = [[NSWorkspace sharedWorkspace] iconForFile:host.bundlePath];
    }
    
    // I don't think any of the further fallbacks are needed but keeping them in case
    
    // Next try a specified icon URL to load the icon from
    if (icon == nil) {
        NSURL *iconURL = [SUBundleIcon iconURLForHost:host];
        icon = (iconURL == nil) ? nil : [[NSImage alloc] initWithContentsOfURL:iconURL];
    }
    
    // Next try standard app icon from asset catalog
    if (!icon) {
        icon = [host.bundle imageForResource:@SPARKLE_ICON_NAME];
    }
    
    // Use a default generic icon if none is defined.
    if (!icon) {
        // this assumption may not be correct (eg. even though we're not the main bundle, it could be still be a regular app)
        // but still better than nothing if no icon was included
        if (@available(macOS 11, *)) {
            UTType *contentType = isMainBundle ? UTTypeApplication : UTTypeBundle;
            icon = [[NSWorkspace sharedWorkspace] iconForContentType:contentType];
        }
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_VERSION_11_0
        else
        {
            NSString *fileType = isMainBundle ? (__bridge NSString *)kUTTypeApplication : (__bridge NSString *)kUTTypeBundle;
            icon = [[NSWorkspace sharedWorkspace] iconForFileType:fileType];
        }
#endif
    }
    return icon;
}

@end

#endif
