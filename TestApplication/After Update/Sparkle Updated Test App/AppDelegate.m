//
//  AppDelegate.m
//  Sparkle Updated Test App
//
//  Created by Kornel on 26/07/2014.
//  Copyright (c) 2014 Sparkle-project. All rights reserved.
//

#import "AppDelegate.h"

@interface AppDelegate ()
@end

@implementation AppDelegate
            
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    NSRunAlertPanel(@"Update succeeded!", @"This is the updated version of Sparkle Test App.\n\nDelete and rebuild the app to test updates again.", @"OK", nil, nil);

    NSURL *bundleURL = [NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];
    if (bundleURL) {
        [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs: @[bundleURL]];
    }
    
    [NSApp terminate:self];
}

@end
