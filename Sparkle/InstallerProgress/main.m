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
        ShowInstallerProgress *showInstallerProgress = [[ShowInstallerProgress alloc] init];
        
        InstallerProgressAppController *appController =
        [[InstallerProgressAppController alloc]
         initWithApplication:[NSApplication sharedApplication]
         arguments:[[NSProcessInfo processInfo] arguments]
         delegate:showInstallerProgress];
        
        [appController run];
    }
    
    return EXIT_SUCCESS;
}
