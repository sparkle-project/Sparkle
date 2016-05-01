//
//  main.m
//  sparkle-cli
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

int main(int argc, const char *argv[])
{
    @autoreleasepool
    {
        if (argc != 3) {
            printf("Usage: %s <update-bundle-path> <relaunch-app-path>\n", argv[0]);
            return EXIT_FAILURE;
        }
        
        AppDelegate *delegate = [[AppDelegate alloc] initWithUpdateBundlePath:argv[1] relaunchBundlePath:argv[2]];
        if (delegate == nil) {
            printf("Error: Failed to initialize sparkle. Is the bundle you specified valid?\n");
            return EXIT_FAILURE;
        }
        
        NSApplication *application = [NSApplication sharedApplication];
        [application setDelegate:delegate];
        
        [application run];
    }
    
    return EXIT_SUCCESS;
}
