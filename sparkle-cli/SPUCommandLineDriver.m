//
//  SUCommandLineDriver.m
//  sparkle-cli
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUCommandLineDriver.h"
#import <SparkleCore/SparkleCore.h>
#import "SPUCommandLineUserDriver.h"

@interface SPUCommandLineDriver () <SPUUpdaterDelegate>

@property (nonatomic, readonly) SPUUpdater *updater;
@property (nonatomic, readonly) BOOL verbose;
@property (nonatomic) BOOL probingForUpdates;
@property (nonatomic, readonly) BOOL interactive;
@property (nonatomic, copy, readonly, nullable) NSString *customFeedURL;

@end

@implementation SPUCommandLineDriver

@synthesize updater = _updater;
@synthesize verbose = _verbose;
@synthesize probingForUpdates = _probingForUpdates;
@synthesize interactive = _interactive;
@synthesize customFeedURL = _customFeedURL;

- (instancetype)initWithUpdateBundlePath:(NSString *)updateBundlePath applicationBundlePath:(nullable NSString *)applicationBundlePath customFeedURL:(nullable NSString *)customFeedURL updatePermissionResponse:(nullable SUUpdatePermissionResponse *)updatePermissionResponse deferInstallation:(BOOL)deferInstallation interactiveInstallation:(BOOL)interactiveInstallation verbose:(BOOL)verbose
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
        _customFeedURL = [customFeedURL copy];
        
        id <SPUUserDriver> userDriver = [[SPUCommandLineUserDriver alloc] initWithUpdatePermissionResponse:updatePermissionResponse deferInstallation:deferInstallation verbose:verbose];
        _updater = [[SPUUpdater alloc] initWithHostBundle:updateBundle applicationBundle:applicationBundle userDriver:userDriver delegate:self];
    }
    return self;
}

// Because the user driver dispatches to the main queue asynchronously, we should do so here too
// to preserve the order of handled events

- (void)updater:(SPUUpdater *)__unused updater willScheduleUpdateCheckAfterDelay:(NSTimeInterval)delay
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.verbose) {
            fprintf(stderr, "Last update check occurred too soon. Try again after %0.0f second(s).", delay);
        }
        exit(EXIT_SUCCESS);
    });
}

- (void)updaterWillIdleSchedulingUpdates:(SPUUpdater *)__unused updater
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.verbose) {
            fprintf(stderr, "Automatic update checks are disabled. Exiting.\n");
        }
        exit(EXIT_SUCCESS);
    });
}

// If the installation is interactive, we can show an authorization prompt for requesting additional privileges,
// along with allowing the installer to show UI when installing
- (BOOL)updater:(SPUUpdater *)__unused updater shouldAllowInstallerInteractionForScheduledChecks:(SPUUpdateCheck)updateCheck
{
    switch (updateCheck) {
        case SPUUpdateCheckUserInitiated:
        case SPUUpdateCheckBackgroundScheduled:
            return self.interactive;
    }
}

- (nullable NSString *)feedURLStringForUpdater:(SPUUpdater *)__unused updater
{
    return self.customFeedURL;
}

// In case we find an update during probing, otherwise we leave this to the user driver
- (void)updater:(SPUUpdater *)__unused updater didFindValidUpdate:(SUAppcastItem *)__unused item
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.probingForUpdates) {
            if (self.verbose) {
                fprintf(stderr, "Update available!\n");
            }
            exit(EXIT_SUCCESS);
        }
    });
}

- (void)updaterDidNotFindUpdate:(SPUUpdater *)__unused updater
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.verbose) {
            fprintf(stderr, "No update available!\n");
        }
        exit(EXIT_FAILURE);
    });
}

- (void)updater:(SPUUpdater *)__unused updater didAbortWithError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.verbose) {
            fprintf(stderr, "Aborted update with error (%ld): %s\n", (long)error.code, error.localizedDescription.UTF8String);
        }
        exit(EXIT_FAILURE);
    });
}

- (BOOL)updaterShouldDownloadReleaseNotes:(SPUUpdater *)__unused updater
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
