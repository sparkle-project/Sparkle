//
//  main.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "InstallerProgressAppController.h"
#import "ShowInstallerProgress.h"

int main(int __unused argc, const char __unused *argv[])
{
    @autoreleasepool
    {
        id<InstallerProgressDelegate> showInstallerProgress = [[ShowInstallerProgress alloc] init];
        
        InstallerProgressAppController *appController =
        [[InstallerProgressAppController alloc]
         initWithApplication:[NSApplication sharedApplication]
         arguments:[[NSProcessInfo processInfo] arguments]
         delegate:showInstallerProgress];
        
        // Ignore SIGTERM because we are going to catch it ourselves
        signal(SIGTERM, SIG_IGN);
        
        dispatch_source_t sigtermSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
        dispatch_source_set_event_handler(sigtermSource, ^{
            [appController cleanupAndExitWithStatus:SIGTERM error:nil];
        });
        dispatch_resume(sigtermSource);
        
        [appController run];
    }
    
    return EXIT_SUCCESS;
}
