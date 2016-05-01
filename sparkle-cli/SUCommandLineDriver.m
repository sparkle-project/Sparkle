//
//  SUCommandLineDriver.m
//  sparkle-cli
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUCommandLineDriver.h"
#import <Sparkle/Sparkle.h>
#import "SUCommandLineUserDriver.h"

@interface SUCommandLineDriver () <SUUpdaterDelegate>

@property (nonatomic, readonly) SUUpdater *updater;
@property (nonatomic, readonly) NSString *relaunchBundlePath;

@end

@implementation SUCommandLineDriver

@synthesize updater = _updater;
@synthesize relaunchBundlePath = _relaunchBundlePath;

- (instancetype)initWithUpdateBundlePath:(const char *)updateBundlePathString relaunchBundlePath:(const char *)relaunchBundlePathString
{
    self = [super init];
    if (self != nil) {
        NSString *updateBundlePath = [[NSString alloc] initWithUTF8String:updateBundlePathString];
        if (updateBundlePath == nil) {
            return nil;
        }
        
        NSString *relaunchBundlePath = [[NSString alloc] initWithUTF8String:relaunchBundlePathString];
        if (relaunchBundlePath == nil) {
            return nil;
        }
        
        NSBundle *updateBundle = [NSBundle bundleWithPath:updateBundlePath];
        if (updateBundle == nil) {
            return nil;
        }
        
        NSBundle *relaunchBundle = [NSBundle bundleWithPath:relaunchBundlePath];
        if (relaunchBundle == nil) {
            return nil;
        }
        
        _relaunchBundlePath = relaunchBundlePath;
        
        id <SUUserDriver> userDriver = [[SUCommandLineUserDriver alloc] initWithRelaunchBundle:relaunchBundle];
        _updater = [[SUUpdater alloc] initWithHostBundle:updateBundle userDriver:userDriver delegate:self];
    }
    return self;
}

- (BOOL)updaterShouldInheritInstallPrivileges:(SUUpdater *)__unused updater
{
    return YES;
}

- (NSString *)pathToRelaunchForUpdater:(SUUpdater *)__unused updater
{
    return self.relaunchBundlePath;
}

- (void)run
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
