//
//  SUCommandLineDriver.m
//  sparkle-cli
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUCommandLineDriver.h"
#import <Sparkle/Sparkle.h>
#import <Sparkle/SUInstallerLauncher+Private.h>
#import "SPUCommandLineUserDriver.h"

@interface SPUCommandLineDriver () <SPUUpdaterDelegate>

@property (nonatomic, readonly) SPUUpdater *updater;
@property (nonatomic, readonly) BOOL verbose;
@property (nonatomic) BOOL probingForUpdates;
@property (nonatomic, readonly) BOOL interactive;
@property (nonatomic, readonly) BOOL allowMajorUpgrades;
@property (nonatomic, readonly) NSSet<NSString *> *allowedChannels;
@property (nonatomic, copy, readonly, nullable) NSString *customFeedURL;

@end

@implementation SPUCommandLineDriver

@synthesize updater = _updater;
@synthesize verbose = _verbose;
@synthesize probingForUpdates = _probingForUpdates;
@synthesize interactive = _interactive;
@synthesize allowMajorUpgrades = _allowMajorUpgrades;
@synthesize allowedChannels = _allowedChannels;
@synthesize customFeedURL = _customFeedURL;

- (instancetype)initWithUpdateBundlePath:(NSString *)updateBundlePath applicationBundlePath:(nullable NSString *)applicationBundlePath allowedChannels:(NSSet<NSString *> *)allowedChannels customFeedURL:(nullable NSString *)customFeedURL updatePermissionResponse:(nullable SUUpdatePermissionResponse *)updatePermissionResponse deferInstallation:(BOOL)deferInstallation interactiveInstallation:(BOOL)interactiveInstallation allowMajorUpgrades:(BOOL)allowMajorUpgrades verbose:(BOOL)verbose
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
        _allowMajorUpgrades = allowMajorUpgrades;
        _allowedChannels = allowedChannels;
        _customFeedURL = [customFeedURL copy];
        
        id <SPUUserDriver> userDriver = [[SPUCommandLineUserDriver alloc] initWithUpdatePermissionResponse:updatePermissionResponse deferInstallation:deferInstallation verbose:verbose];
        _updater = [[SPUUpdater alloc] initWithHostBundle:updateBundle applicationBundle:applicationBundle userDriver:userDriver delegate:self];
    }
    return self;
}

- (void)updater:(SPUUpdater *)__unused updater willScheduleUpdateCheckAfterDelay:(NSTimeInterval)delay __attribute__((noreturn))
{
    if (self.verbose) {
        fprintf(stderr, "Last update check occurred too soon. Try again after %0.0f second(s).", delay);
    }
    exit(EXIT_SUCCESS);
}

- (void)updaterWillNotScheduleUpdateCheck:(SPUUpdater *)__unused updater __attribute__((noreturn))
{
    if (self.verbose) {
        fprintf(stderr, "Automatic update checks are disabled. Exiting.\n");
    }
    exit(EXIT_SUCCESS);
}

// If the installation is not interactive, we should not perform an update check if we don't have permission to update the bundle path
- (BOOL)updaterMayCheckForUpdates:(SPUUpdater *)updater updateCheck:(SPUUpdateCheck)updateCheck
{
    switch (updateCheck) {
        case SPUUpdateCheckUpdates:
        case SPUUpdateCheckUpdatesInBackground:
            return (self.interactive || !SPUSystemNeedsAuthorizationAccessForBundlePath(self.updater.hostBundle.bundlePath));
        case SPUUpdateCheckUpdateInformation:
            return YES;
    }
}

// If the installation is not interactive, we should only proceed with application based updates and not package-based ones
- (BOOL)updater:(SPUUpdater *)updater shouldProceedWithUpdate:(nonnull SUAppcastItem *)updateItem error:(NSError *__autoreleasing  _Nullable * _Nullable)error
{
    return (self.interactive || [updateItem.installationType isEqualToString:SPUInstallationTypeApplication]);
}

- (NSSet<NSString *> *)allowedChannelsForUpdater:(SPUUpdater *)__unused updater
{
    return self.allowedChannels;
}

- (nullable NSString *)feedURLStringForUpdater:(SPUUpdater *)__unused updater
{
    return self.customFeedURL;
}

// In case we find an update during probing, otherwise we leave this to the user driver
- (void)updater:(SPUUpdater *)__unused updater didFindValidUpdate:(SUAppcastItem *)item
{
    // If we encounter a major upgrade and not allowed to act on it, then exit(2)
    if (item.majorUpgrade && !self.allowMajorUpgrades) {
        if (self.verbose) {
            fprintf(stderr, "Major upgrade available");
            if (self.probingForUpdates) {
                fprintf(stderr, "\n");
            } else {
                fprintf(stderr, " but not allowed to install it.\n");
            }
        }
        exit(2);
    } else if (self.probingForUpdates) {
        if (self.verbose) {
            fprintf(stderr, "Update available!\n");
        }
        exit(EXIT_SUCCESS);
    }
}

- (void)updaterDidNotFindUpdate:(SPUUpdater *)__unused updater __attribute__((noreturn))
{
    if (self.verbose) {
        fprintf(stderr, "No update available!\n");
    }
    exit(EXIT_FAILURE);
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
    [self startUpdater];
    
    if (checkForUpdatesNow) {
        // When we start the updater, this scheduled check will start afterwards too
        [self.updater checkForUpdates];
    }
}

- (void)probeForUpdates
{
    [self startUpdater];
    
    // When we start the updater, this info check will start afterwards too
    self.probingForUpdates = YES;
    [self.updater checkForUpdateInformation];
}

@end
