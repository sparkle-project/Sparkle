//
//  SUCommandLineUserDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUCommandLineUserDriver.h"
#import <AppKit/AppKit.h>

#define SCHEDULED_UPDATE_TIMER_THRESHOLD 2.0 // seconds

@interface SUCommandLineUserDriver ()

@property (nonatomic, readonly) NSBundle *applicationBundle;
@property (nonatomic, nullable, readonly) SUUpdatePermission *updatePermission;
@property (nonatomic, readonly) BOOL deferInstallation;
@property (nonatomic, readonly) BOOL verbose;
@property (nonatomic, readonly) SUUserDriverCoreComponent *coreComponent;
@property (nonatomic) NSUInteger bytesDownloaded;
@property (nonatomic) NSUInteger bytesToDownload;

@end

@implementation SUCommandLineUserDriver

@synthesize applicationBundle = _applicationBundle;
@synthesize updatePermission = _updatePermission;
@synthesize deferInstallation = _deferInstallation;
@synthesize verbose = _verbose;
@synthesize coreComponent = _coreComponent;
@synthesize bytesDownloaded = _bytesDownloaded;
@synthesize bytesToDownload = _bytesToDownload;

- (instancetype)initWithApplicationBundle:(NSBundle *)applicationBundle updatePermission:(nullable SUUpdatePermission *)updatePermission deferInstallation:(BOOL)deferInstallation verbose:(BOOL)verbose
{
    self = [super init];
    if (self != nil) {
        _applicationBundle = applicationBundle;
        _updatePermission = updatePermission;
        _deferInstallation = deferInstallation;
        _verbose = verbose;
        _coreComponent = [[SUUserDriverCoreComponent alloc] initWithDelegate:nil];
    }
    return self;
}

- (void)showCanCheckForUpdates:(BOOL)canCheckForUpdates
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent showCanCheckForUpdates:canCheckForUpdates];
    });
}

- (void)idleOnUpdateChecks:(BOOL)shouldIdleOnUpdateChecks
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (shouldIdleOnUpdateChecks) {
            fprintf(stderr, "Error: Automatic update checking is disabled.\n");
            exit(EXIT_FAILURE);
        }
        
        [self.coreComponent idleOnUpdateChecks:shouldIdleOnUpdateChecks];
    });
}

- (void)startUpdateCheckTimerWithNextTimeInterval:(NSTimeInterval)timeInterval reply:(void (^)(SUUpdateCheckTimerStatus))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (timeInterval > SCHEDULED_UPDATE_TIMER_THRESHOLD) {
            if (self.verbose) {
                fprintf(stderr, "Too early to check for new updates. Next check is in %f seconds. Exiting.\n", timeInterval);
            }
            exit(EXIT_SUCCESS);
        } else {
            [self.coreComponent startUpdateCheckTimerWithNextTimeInterval:timeInterval reply:reply];
        }
    });
}

- (void)invalidateUpdateCheckTimer
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent invalidateUpdateCheckTimer];
    });
}

- (void)requestUpdatePermissionWithSystemProfile:(NSArray *)__unused systemProfile reply:(void (^)(SUUpdatePermission *))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.updatePermission == nil) {
            // We don't want to make this decision on behalf of the user.
            fprintf(stderr, "Error: Asked to grant update permission. Exiting.\n");
            exit(EXIT_FAILURE);
        } else {
            if (self.verbose) {
                fprintf(stderr, "Granting permission for automatic update checks with sending system profile %s...\n", self.updatePermission.sendProfile ? "enabled" : "disabled");
            }
            reply(self.updatePermission);
        }
    });
}

- (void)showUserInitiatedUpdateCheckWithCompletion:(void (^)(SUUserInitiatedCheckStatus))updateCheckStatusCompletion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent registerUpdateCheckStatusHandler:updateCheckStatusCompletion];
        if (self.verbose) {
            fprintf(stderr, "Checking for Updates...\n");
        }
    });
}

- (void)dismissUserInitiatedUpdateCheck
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent completeUpdateCheckStatus];
    });
}

- (void)displayReleaseNotes:(NSData *)releaseNotes
{
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithHTML:releaseNotes documentAttributes:NULL];
    fprintf(stderr, "Release notes:\n");
    fprintf(stderr, "%s\n", attributedString.string.UTF8String);
}

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem allowsAutomaticUpdates:(BOOL)__unused allowsAutomaticUpdates alreadyDownloaded:(BOOL)__unused alreadyDownloaded reply:(void (^)(SUUpdateAlertChoice))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.verbose) {
            fprintf(stderr, "Found new update! (%s)\n", appcastItem.displayVersionString.UTF8String);
            
            if (appcastItem.itemDescription != nil) {
                NSData *descriptionData = [appcastItem.itemDescription dataUsingEncoding:NSUTF8StringEncoding];
                if (descriptionData != nil) {
                    [self displayReleaseNotes:descriptionData];
                }
            }
        }
        reply(SUInstallUpdateChoice);
    });
}

- (void)showUpdateReleaseNotes:(NSData *)releaseNotes
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.verbose) {
            [self displayReleaseNotes:releaseNotes];
        }
    });
}

- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.verbose) {
            fprintf(stderr, "Error: Unable to download release notes: %s\n", error.localizedDescription.UTF8String);
        }
    });
}

- (void)showUpdateNotFoundWithAcknowledgement:(void (^)(void))__unused acknowledgement
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.verbose) {
            fprintf(stderr, "No new update available!\n");
        }
        exit(EXIT_SUCCESS);
    });
}

- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))__unused acknowledgement
{
    dispatch_async(dispatch_get_main_queue(), ^{
        fprintf(stderr, "Error: Update has failed: %s\n", error.localizedDescription.UTF8String);
        exit(EXIT_FAILURE);
    });
}

- (void)showDownloadInitiatedWithCompletion:(void (^)(SUDownloadUpdateStatus))downloadUpdateStatusCompletion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent registerDownloadStatusHandler:downloadUpdateStatusCompletion];
        
        if (self.verbose) {
            fprintf(stderr, "Downloading Update...\n");
        }
    });
}

- (void)showDownloadDidReceiveExpectedContentLength:(int64_t)expectedContentLength
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.verbose) {
            fprintf(stderr, "Downloading %llu bytes...\n", expectedContentLength);
        }
        self.bytesDownloaded = 0;
        self.bytesToDownload = (NSUInteger)expectedContentLength;
    });
}

- (void)showDownloadDidReceiveDataOfLength:(NSUInteger)length
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.bytesDownloaded += length;
        if (self.bytesToDownload > 0 && self.verbose) {
            fprintf(stderr, "Downloaded %lu out of %lu bytes (%.0f%%)\n", (unsigned long)self.bytesDownloaded, (unsigned long)self.bytesToDownload, (self.bytesDownloaded * 100.0 / self.bytesToDownload));
        }
    });
}

- (void)showDownloadFinishedAndStartedExtractingUpdate
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent completeDownloadStatus];
        
        if (self.verbose) {
            fprintf(stderr, "Extracting update...\n");
        }
    });
}

- (void)showExtractionReceivedProgress:(double)progress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.verbose) {
            fprintf(stderr, "Extracting Update (%.0f%%)\n", progress * 100);
        }
    });
}

- (void)showReadyToInstallAndRelaunch:(void (^)(SUInstallUpdateStatus))installUpdateHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent registerInstallUpdateHandler:installUpdateHandler];
        
        if (self.deferInstallation) {
            if (self.verbose) {
                fprintf(stderr, "Deferring Installation.\n");
            }
            [self.coreComponent installUpdateWithChoice:SUDismissUpdateInstallation];
        } else if ([self targetRunningApplication] != nil) {
            [self.coreComponent installUpdateWithChoice:SUInstallAndRelaunchUpdateNow];
        } else {
            [self.coreComponent installUpdateWithChoice:SUInstallUpdateNow];
        }
    });
}

- (void)showInstallingUpdate
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.verbose) {
            fprintf(stderr, "Installing Update...\n");
        }
    });
}

- (void)showUpdateInstallationDidFinish
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.verbose) {
           fprintf(stderr, "Installation Finished.\n");
        }
    });
}

- (void)dismissUpdateInstallation
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.verbose) {
            fprintf(stderr, "Exiting.\n");
        }
        exit(EXIT_SUCCESS);
    });
}

- (void)terminateApplication
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSRunningApplication *runningApplication = [self targetRunningApplication];
        if (runningApplication != nil) {
            if (![runningApplication terminate]) {
                if (![runningApplication forceTerminate]) {
                    fprintf(stderr, "Error: Failed to terminate running application. Please terminate it to update it.");
                    exit(EXIT_FAILURE);
                }
            }
        }
    });
}

- (NSRunningApplication *)targetRunningApplication
{
    NSString *bundleIdentifier = self.applicationBundle.bundleIdentifier;
    if (bundleIdentifier != nil) {
        NSArray<NSRunningApplication *> *runningApplications = [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier];
        // Make sure we *don't* use NSURLs for equality comparison; turns out to not work that great
        NSString *bundlePath = self.applicationBundle.bundleURL.path;
        if (bundlePath != nil) {
            for (NSRunningApplication *runningApplication in runningApplications) {
                NSString *candidatePath = runningApplication.bundleURL.path;
                if (candidatePath != nil && [bundlePath isEqualToString:candidatePath]) {
                    return runningApplication;
                }
            }
        }
    }
    return nil;
}

@end
