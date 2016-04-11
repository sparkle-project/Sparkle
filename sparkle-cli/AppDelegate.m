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

@property (nonatomic, readonly) NSBundle *bundle;
@property (nonatomic) SUUpdater *updater;

@end

@implementation AppDelegate

@synthesize bundle = _bundle;
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
        
        _bundle = bundle;
    }
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)__unused aNotification
{
    id <SUUserDriver> userDriver = [[SUCommandLineUserDriver alloc] initWithBundle:self.bundle];
    self.updater = [[SUUpdater alloc] initWithHostBundle:self.bundle userDriver:userDriver delegate:nil];
    [self.updater checkForUpdates];
}

@end
