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
#import <Sparkle/SPUUserAgent+Private.h>
#import "SPUCommandLineUserDriver.h"

#define SPARKLE_CLI_ERROR_DOMAIN @"sparkle-cli"

typedef NS_ENUM(NSInteger, CLIErrorCode) {
    CLIErrorCodeCannotPerformCheck = 1,
    CLIErrorCodeCannotInstallPackage,
    CLIErrorCodeCannotInstallMajorUpgrade
};

typedef NS_ENUM(int, CLIErrorExitStatus) {
    CLIErrorExitStatusMajorUpgradeNotAllowed = 2,
    CLIErrorExitStatusInstallerInteractionNotAllowed = 3,
    CLIErrorExitStatusUpdateNotFound = 4,
    CLIErrorExitStatusUpdateCancelledAuthorization = 5,
    CLIErrorExitStatusUpdatePermissionRequested = 6
};

@interface SPUCommandLineDriver () <SPUUpdaterDelegate>

@property (nonatomic, readonly) SPUUpdater *updater;
@property (nonatomic, readonly) BOOL verbose;
@property (nonatomic) BOOL probingForUpdates;
@property (nonatomic, readonly) BOOL interactive;
@property (nonatomic, readonly) BOOL allowMajorUpgrades;
@property (nonatomic, readonly) NSSet<NSString *> *allowedChannels;
@property (nonatomic, copy, readonly, nullable) NSString *customFeedURL;
@property (nonatomic, readonly) SUUpdatePermissionResponse *updatePermissionResponse;

@end

@implementation SPUCommandLineDriver

@synthesize updater = _updater;
@synthesize verbose = _verbose;
@synthesize probingForUpdates = _probingForUpdates;
@synthesize interactive = _interactive;
@synthesize allowMajorUpgrades = _allowMajorUpgrades;
@synthesize allowedChannels = _allowedChannels;
@synthesize customFeedURL = _customFeedURL;
@synthesize updatePermissionResponse = _updatePermissionResponse;

- (instancetype)initWithUpdateBundlePath:(NSString *)updateBundlePath applicationBundlePath:(nullable NSString *)applicationBundlePath allowedChannels:(NSSet<NSString *> *)allowedChannels customFeedURL:(nullable NSString *)customFeedURL userAgentName:(nullable NSString *)customUserAgentName updatePermissionResponse:(nullable SUUpdatePermissionResponse *)updatePermissionResponse deferInstallation:(BOOL)deferInstallation interactiveInstallation:(BOOL)interactiveInstallation allowMajorUpgrades:(BOOL)allowMajorUpgrades verbose:(BOOL)verbose
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
        _updatePermissionResponse = updatePermissionResponse;
        
        id <SPUUserDriver> userDriver = [[SPUCommandLineUserDriver alloc] initWithUpdatePermissionResponse:updatePermissionResponse deferInstallation:deferInstallation verbose:verbose];
        _updater = [[SPUUpdater alloc] initWithHostBundle:updateBundle applicationBundle:applicationBundle userDriver:userDriver delegate:self];
        
        {
            // Retrieve a suitable user agent.
            NSString *userAgentString;
            NSBundle *mainBundle = [NSBundle mainBundle];
            if (customUserAgentName != nil) {
                // Let's use the user agent name that the user passed to us
                userAgentString = SPUMakeUserAgentWithBundle(mainBundle, [NSString stringWithFormat:@" (%@)", customUserAgentName]);
            } else {
                // Are we embedded inside of another responsible app?
                NSURL *parentDirectoryURL = mainBundle.bundleURL.URLByDeletingLastPathComponent;
                NSURL *parentParentDirectoryURL = parentDirectoryURL.URLByDeletingLastPathComponent;
                
                if ([parentParentDirectoryURL.lastPathComponent isEqualToString:@"Contents"] && ([parentDirectoryURL.lastPathComponent isEqualToString:@"Resources"] || [parentDirectoryURL.lastPathComponent isEqualToString:@"MacOS"] || [parentDirectoryURL.lastPathComponent isEqualToString:@"Helpers"])) {
                    NSURL *responsibleApplicationURL = parentParentDirectoryURL.URLByDeletingLastPathComponent;
                    NSBundle *responsibleBundle = [NSBundle bundleWithURL:responsibleApplicationURL];
                    if (responsibleBundle == nil) {
                        userAgentString = SPUMakeUserAgentWithBundle(mainBundle, nil);
                    } else {
                        userAgentString = SPUMakeUserAgentWithBundle(responsibleBundle, @" (sparkle)");
                    }
                } else {
                    userAgentString = SPUMakeUserAgentWithBundle(mainBundle, nil);
                }
            }
            
            _updater.userAgentString = userAgentString;
        }
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

- (BOOL)updaterShouldPromptForPermissionToCheckForUpdates:(SPUUpdater *)__unused updater
{
    if (self.updatePermissionResponse == nil) {
        // We don't want to make this decision on behalf of the user.
        fprintf(stderr, "Error: Asked to grant update permission and --grant-automatic-checks is not specified. Exiting.\n");
        exit(CLIErrorExitStatusUpdatePermissionRequested);
    }
    
    return YES;
}

// If the installation is not interactive, we should not perform an update check if we don't have permission to update the bundle path
- (BOOL)updater:(SPUUpdater *)updater mayPerformUpdateCheck:(SPUUpdateCheck)updateCheck error:(NSError * __autoreleasing *)error
{
    switch (updateCheck) {
        case SPUUpdateCheckUpdates:
        case SPUUpdateCheckUpdatesInBackground:
            if (self.interactive || !SPUSystemNeedsAuthorizationAccessForBundlePath(self.updater.hostBundle.bundlePath)) {
                return YES;
            }
            
            if (error != NULL) {
                *error = [NSError errorWithDomain:SPARKLE_CLI_ERROR_DOMAIN code:CLIErrorCodeCannotPerformCheck userInfo:@{ NSLocalizedDescriptionKey: @"A new update check cannot be performed because updating this bundle will require user authorization. Please use --interactive to allow this." }];
            }
            
            return NO;
        case SPUUpdateCheckUpdateInformation:
            return YES;
    }
}

// If the installation is not interactive, we should only proceed with application based updates and not package-based ones
- (BOOL)updater:(SPUUpdater *)updater shouldProceedWithUpdate:(nonnull SUAppcastItem *)updateItem updateCheck:(SPUUpdateCheck)updateCheck error:(NSError * __autoreleasing *)error
{
    // We can always probe for update information
    if (updateCheck == SPUUpdateCheckUpdateInformation) {
        return YES;
    }
    
    // If we encounter a major upgrade and not allowed to act on it, then error
    if (updateItem.majorUpgrade && !self.allowMajorUpgrades) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SPARKLE_CLI_ERROR_DOMAIN code:CLIErrorCodeCannotInstallMajorUpgrade userInfo:@{ NSLocalizedDescriptionKey: @"Major upgrade available but not allowed to install it. Pass --allow-major-upgrades to allow this." }];
        }
        
        return NO;
    }
    
    if (!self.interactive && ![updateItem.installationType isEqualToString:SPUInstallationTypeApplication]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SPARKLE_CLI_ERROR_DOMAIN code:CLIErrorCodeCannotInstallPackage userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"A new package-based update has been found (%@), but installing it will require user authorization. Please use --interactive to allow this.", updateItem.versionString] }];
        }
        
        return NO;
    }
    
    return YES;
}

- (NSSet<NSString *> *)allowedChannelsForUpdater:(SPUUpdater *)__unused updater
{
    return self.allowedChannels;
}

- (nullable NSString *)feedURLStringForUpdater:(SPUUpdater *)__unused updater
{
    return self.customFeedURL;
}

// In case we find an update during probing
- (void)updater:(SPUUpdater *)__unused updater didFindValidUpdate:(SUAppcastItem *)item
{
    if (self.probingForUpdates) {
        if (self.verbose) {
            if (item.majorUpgrade) {
                fprintf(stderr, "Major upgrade available.\n");
            } else {
                fprintf(stderr, "Update available!\n");
            }
        }
    }
}

- (void)updater:(SPUUpdater *)updater didFinishUpdateCycleForUpdateCheck:(SPUUpdateCheck)__unused updateCheck error:(nullable NSError *)error __attribute__((noreturn))
{
    if (error == nil) {
        if (self.verbose) {
            fprintf(stderr, "Exiting.\n");
        }
        exit(EXIT_SUCCESS);
    } else if ([error.domain isEqualToString:SPARKLE_CLI_ERROR_DOMAIN]) {
        fprintf(stderr, "%s\n", error.localizedDescription.UTF8String);
        
        if (error.code == CLIErrorCodeCannotInstallMajorUpgrade) {
            // Major upgrades are not allowed
            exit(CLIErrorExitStatusMajorUpgradeNotAllowed);
        } else {
            // This is one of our own interactive update failures
            exit(CLIErrorExitStatusInstallerInteractionNotAllowed);
        }
    } else if (error.code == SUNoUpdateError) {
        if (self.verbose) {
            fprintf(stderr, "No new update available!\n");
        }
        exit(CLIErrorExitStatusUpdateNotFound);
    } else if (error.code == SUInstallationCanceledError) {
        // User canceled authorization themselves
        assert(self.interactive);
        if (self.verbose) {
            fprintf(stderr, "Update was cancelled.\n");
        }
        exit(CLIErrorExitStatusUpdateCancelledAuthorization);
    } else {
        fprintf(stderr, "Error: Update has failed due to error %ld (%s). %s\n", (long)error.code, error.domain.UTF8String, error.localizedDescription.UTF8String);
        exit(EXIT_FAILURE);
    }
}

- (BOOL)updater:(SPUUpdater *)updater shouldDownloadReleaseNotesForUpdate:(nonnull SUAppcastItem *)__unused item
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
