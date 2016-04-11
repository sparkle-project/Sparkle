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
        if (argc != 2) {
            printf("Usage: %s <path to bundle to update>\n", argv[0]);
            return EXIT_FAILURE;
        }
        
        AppDelegate *delegate = [[AppDelegate alloc] initWithBundlePath:argv[1]];
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
