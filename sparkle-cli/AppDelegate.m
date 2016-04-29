//
//  AppDelegate.m
//  sparkle-cli
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "AppDelegate.h"
#import <Sparkle/Sparkle.h>
#import "SUCommandLineUserDriver.h"

@interface AppDelegate ()

@property (nonatomic, readonly) SUUpdater *updater;

@end

@implementation AppDelegate

@synthesize updater = _updater;

- (instancetype)initWithBundlePath:(const char *)bundlePath
{
    self = [super init];
    if (self != nil) {
        NSString *bundlePathString = [[NSString alloc] initWithUTF8String:bundlePath];
        if (bundlePathString == nil) {
            return nil;
        }
        
        NSBundle *bundle = [NSBundle bundleWithPath:bundlePathString];
        if (bundle == nil) {
            return nil;
        }
        
        id <SUUserDriver> userDriver = [[SUCommandLineUserDriver alloc] initWithBundle:bundle];
        _updater = [[SUUpdater alloc] initWithHostBundle:bundle userDriver:userDriver delegate:nil];
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)__unused aNotification
{
    // Kick off a scheduled update check once we start the updater later
    [self.updater checkForUpdates];
    
    NSError *updaterError = nil;
    if (![self.updater startUpdater:&updaterError]) {
        printf("Error: Failed to initialize updater with error (%ld): %s\n", updaterError.code, updaterError.localizedDescription.UTF8String);
        exit(EXIT_FAILURE);
    }
}

@end
