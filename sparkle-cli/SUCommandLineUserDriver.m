//
//  SUCommandLineUserDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUCommandLineUserDriver.h"
#import <AppKit/AppKit.h>

@interface SUCommandLineUserDriver ()

@property (nonatomic, readonly) NSBundle *applicationBundle;
@property (nonatomic, readonly) BOOL deferInstallation;
@property (nonatomic, readonly) BOOL verbose;
@property (nonatomic, readonly) SUUserDriverCoreComponent *coreComponent;
@property (nonatomic) NSUInteger bytesDownloaded;
@property (nonatomic) NSUInteger bytesToDownload;

@end

@implementation SUCommandLineUserDriver

@synthesize applicationBundle = _applicationBundle;
@synthesize deferInstallation = _deferInstallation;
@synthesize verbose = _verbose;
@synthesize coreComponent = _coreComponent;
@synthesize bytesDownloaded = _bytesDownloaded;
@synthesize bytesToDownload = _bytesToDownload;

- (instancetype)initWithApplicationBundle:(NSBundle *)applicationBundle deferInstallation:(BOOL)deferInstallation verbose:(BOOL)verbose
{
    self = [super init];
    if (self != nil) {
        _applicationBundle = applicationBundle;
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
        [self.coreComponent idleOnUpdateChecks:shouldIdleOnUpdateChecks];
    });
}

- (void)startUpdateCheckTimerWithNextTimeInterval:(NSTimeInterval)timeInterval reply:(void (^)(SUUpdateCheckTimerStatus))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent startUpdateCheckTimerWithNextTimeInterval:timeInterval reply:reply];
    });
}

- (void)invalidateUpdateCheckTimer
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent invalidateUpdateCheckTimer];
    });
}

- (void)requestUpdatePermissionWithSystemProfile:(NSArray *)__unused systemProfile reply:(void (^)(SUUpdatePermissionPromptResult *))__unused reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // We really shouldn't get here. If we do, we would be in trouble. We don't want to make this decision on behalf of the user.
        fprintf(stderr, "Asked about making update permission decision.. Aborting because this decision should not be made.\n");
        abort();
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

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem allowsAutomaticUpdates:(BOOL)__unused allowsAutomaticUpdates alreadyDownloaded:(BOOL)__unused alreadyDownloaded reply:(void (^)(SUUpdateAlertChoice))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.verbose) {
            fprintf(stderr, "Found new update! (%s)\n", appcastItem.displayVersionString.UTF8String);
        }
        reply(SUInstallUpdateChoice);
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
        fprintf(stderr, "Error: Update check has failed: %s\n", error.description.UTF8String);
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

- (void)showDownloadDidReceiveResponse:(NSURLResponse *)response
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.verbose) {
            fprintf(stderr, "Downloading %llu bytes...\n", response.expectedContentLength);
        }
        self.bytesDownloaded = 0;
        self.bytesToDownload = (NSUInteger)response.expectedContentLength;
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
            fprintf(stderr, "Exiting...\n");
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
