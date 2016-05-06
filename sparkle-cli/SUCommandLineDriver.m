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
@property (nonatomic, readonly) NSString *applicationBundlePath;
@property (nonatomic, readonly) BOOL verbose;
@property (nonatomic) BOOL probingForUpdates;

@end

@implementation SUCommandLineDriver

@synthesize updater = _updater;
@synthesize applicationBundlePath = _applicationBundlePath;
@synthesize verbose = _verbose;
@synthesize probingForUpdates = _probingForUpdates;

- (instancetype)initWithUpdateBundlePath:(NSString *)updateBundlePath applicationBundlePath:(nullable NSString *)applicationBundlePath updatePermission:(nullable SUUpdatePermission *)updatePermission deferInstallation:(BOOL)deferInstallation verbose:(BOOL)verbose
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
        
        _applicationBundlePath = applicationBundle.bundlePath;
        
        id <SUUserDriver> userDriver = [[SUCommandLineUserDriver alloc] initWithApplicationBundle:applicationBundle updatePermission:updatePermission deferInstallation:deferInstallation verbose:verbose];
        _updater = [[SUUpdater alloc] initWithHostBundle:updateBundle userDriver:userDriver delegate:self];
    }
    return self;
}

- (BOOL)updaterShouldInheritInstallPrivileges:(SUUpdater *)__unused updater
{
    return YES;
}

- (void)updater:(SUUpdater *)__unused updater didFindValidUpdate:(SUAppcastItem *)__unused item
{
    if (self.probingForUpdates) {
        if (self.verbose) {
            fprintf(stderr, "Update available!\n");
        }
        exit(EXIT_SUCCESS);
    }
}

- (void)updaterDidNotFindUpdate:(SUUpdater *)__unused updater
{
    if (self.probingForUpdates) {
        if (self.verbose) {
            fprintf(stderr, "No update available!\n");
        }
        exit(EXIT_FAILURE);
    }
}

- (void)updater:(SUUpdater *)__unused updater failedToDownloadUpdate:(SUAppcastItem *)__unused item error:(NSError *)error
{
    if (self.probingForUpdates) {
        if (self.verbose) {
            fprintf(stderr, "Failed to download update with error (%ld): %s\n", (long)error.code, error.localizedDescription.UTF8String);
        }
        exit(EXIT_FAILURE);
    }
}

- (void)updater:(SUUpdater *)__unused updater didAbortWithError:(NSError *)error
{
    if (self.probingForUpdates) {
        if (self.verbose) {
            fprintf(stderr, "Aborted update with error (%ld): %s\n", (long)error.code, error.localizedDescription.UTF8String);
        }
        exit(EXIT_FAILURE);
    }
}

- (NSString *)pathToRelaunchForUpdater:(SUUpdater *)__unused updater
{
    return self.applicationBundlePath;
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
