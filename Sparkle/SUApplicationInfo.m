//
//  SUApplicationInfo.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUApplicationInfo.h"

@implementation SUApplicationInfo

+ (BOOL)isBackgroundApplication:(NSApplication * __nonnull)application
{
    return (application.activationPolicy == NSApplicationActivationPolicyAccessory);
}

+ (NSImage *__nonnull)bestIconForBundle:(NSBundle * __nonnull)bundle
{
    // Cache the application icon.
    NSString *iconPath = [bundle pathForResource:[bundle objectForInfoDictionaryKey:@"CFBundleIconFile"] ofType:@"icns"];
    // According to the OS X docs, "CFBundleIconFile - This key identifies the file containing
    // the icon for the bundle. The filename you specify does not need to include the .icns
    // extension, although it may."
    //
    // However, if it *does* include the '.icns' the above method fails (tested on OS X 10.3.9) so we'll also try:
    if (!iconPath) {
        iconPath = [bundle pathForResource:[bundle objectForInfoDictionaryKey:@"CFBundleIconFile"] ofType:nil];
    }
    NSImage *icon = [[NSImage alloc] initWithContentsOfFile:iconPath];
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
