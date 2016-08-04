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

void _SULogDisableStandardErrorStream(void);

@interface SUCommandLineDriver () <SUUpdaterDelegate>

@property (nonatomic, readonly) SPUUpdater *updater;
@property (nonatomic, readonly) NSString *applicationBundlePath;
@property (nonatomic, readonly) BOOL verbose;
@property (nonatomic) BOOL probingForUpdates;
@property (nonatomic, readonly) BOOL interactive;

@end

@implementation SUCommandLineDriver

@synthesize updater = _updater;
@synthesize applicationBundlePath = _applicationBundlePath;
@synthesize verbose = _verbose;
@synthesize probingForUpdates = _probingForUpdates;
@synthesize interactive = _interactive;

- (instancetype)initWithUpdateBundlePath:(NSString *)updateBundlePath applicationBundlePath:(nullable NSString *)applicationBundlePath updatePermission:(nullable SUUpdatePermission *)updatePermission deferInstallation:(BOOL)deferInstallation interactiveInstallation:(BOOL)interactiveInstallation verbose:(BOOL)verbose
{
    self = [super init];
    if (self != nil) {
        NSBundle *updateBundle = [NSBundle bundleWithPath:updateBundlePath];
        if (updateBundle == nil) {
            return nil;
        }
        
        NSBundle *applicationBundle = nil;
        if (applicationBundlePath == nil) {
            applicationBundle = updateBundle;
        } else {
            applicationBundle = [NSBundle bundleWithPath:(NSString * _Nonnull)applicationBundlePath];
            if (applicationBundle == nil) {
                return nil;
            }
        }
        
        _verbose = verbose;
        _interactive = interactiveInstallation;
        
        _applicationBundlePath = applicationBundle.bundlePath;
        
#ifndef DEBUG
        _SULogDisableStandardErrorStream();
#endif
        
        id <SUUserDriver> userDriver = [[SUCommandLineUserDriver alloc] initWithApplicationBundle:applicationBundle updatePermission:updatePermission deferInstallation:deferInstallation verbose:verbose];
        _updater = [[SUUpdater alloc] initWithHostBundle:updateBundle userDriver:userDriver delegate:self];
    }
    return self;
}

- (BOOL)updaterShouldAllowInstallerInteraction:(id)__unused updater
{
    // If the installation is interactive, we can show an authorization prompt for requesting additional privileges,
    // otherwise we should have the installer inherit the updater's privileges.
    return self.interactive;
}

// In case we find an update during probing, otherwise we leave this to the user driver
- (void)updater:(SUUpdater *)__unused updater didFindValidUpdate:(SUAppcastItem *)__unused item
{
    if (self.probingForUpdates) {
        if (self.verbose) {
            fprintf(stderr, "Update available!\n");
        }
        exit(EXIT_SUCCESS);
    }
}

// In case we fail during probing, otherwise we leave error handling to the user driver
- (void)updaterDidNotFindUpdate:(id)__unused updater
{
    if (self.probingForUpdates) {
        if (self.verbose) {
            fprintf(stderr, "No update available!\n");
        }
        exit(EXIT_FAILURE);
    }
}

// In case we fail during probing, otherwise we leave error handling to the user driver
- (void)updater:(id)__unused updater didAbortWithError:(NSError *)error
{
    if (self.probingForUpdates) {
        if (self.verbose) {
            fprintf(stderr, "Aborted update with error (%ld): %s\n", (long)error.code, error.localizedDescription.UTF8String);
        }
        exit(EXIT_FAILURE);
    }
}

- (NSString *)pathToRelaunchForUpdater:(id)__unused updater
{
    return self.applicationBundlePath;
}

- (BOOL)updaterShouldDownloadReleaseNotes:(id)__unused updater
{
    return self.verbose;
}

- (void)startUpdater
{
    NSError *updaterError = nil;
    if (![self.updater startUpdater:&updaterError]) {
        fprintf(stderr, "Error: Failed to initialize updater with error (%ld): %s\n", updaterError.code, updaterError.localizedDescription.UTF8String);
        exit(EXIT_FAILURE);
    }
}

- (void)runAndCheckForUpdatesNow:(BOOL)checkForUpdatesNow
{
    if (checkForUpdatesNow) {
        // When we start the updater, this scheduled check will start afterwards too
        [self.updater checkForUpdates];
    }
    
    [self startUpdater];
}

- (void)probeForUpdates
{
    // When we start the updater, this info check will start afterwards too
    self.probingForUpdates = YES;
    [self.updater checkForUpdateInformation];
    [self startUpdater];
}

@end
