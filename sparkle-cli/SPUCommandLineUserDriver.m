//
//  SUCommandLineUserDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUCommandLineUserDriver.h"
#import <AppKit/AppKit.h>
#import <SparkleCore/SparkleCore.h>

#define SCHEDULED_UPDATE_TIMER_THRESHOLD 2.0 // seconds

@interface SPUCommandLineUserDriver ()

@property (nonatomic, nullable, readonly) SUUpdatePermissionResponse *updatePermissionResponse;
@property (nonatomic, readonly) BOOL deferInstallation;
@property (nonatomic, readonly) BOOL verbose;
@property (nonatomic, readonly) SPUUserDriverCoreComponent *coreComponent;
@property (nonatomic) uint64_t bytesDownloaded;
@property (nonatomic) uint64_t bytesToDownload;

@end

@implementation SPUCommandLineUserDriver

@synthesize updatePermissionResponse = _updatePermissionResponse;
@synthesize deferInstallation = _deferInstallation;
@synthesize verbose = _verbose;
@synthesize coreComponent = _coreComponent;
@synthesize bytesDownloaded = _bytesDownloaded;
@synthesize bytesToDownload = _bytesToDownload;

- (instancetype)initWithUpdatePermissionResponse:(nullable SUUpdatePermissionResponse *)updatePermissionResponse deferInstallation:(BOOL)deferInstallation verbose:(BOOL)verbose
{
    self = [super init];
    if (self != nil) {
        _updatePermissionResponse = updatePermissionResponse;
        _deferInstallation = deferInstallation;
        _verbose = verbose;
        _coreComponent = [[SPUUserDriverCoreComponent alloc] init];
    }
    return self;
}

- (void)showCanCheckForUpdates:(BOOL)canCheckForUpdates
{
}

- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)__unused request reply:(void (^)(SUUpdatePermissionResponse *))reply
{
    if (self.updatePermissionResponse == nil) {
        // We don't want to make this decision on behalf of the user.
        fprintf(stderr, "Error: Asked to grant update permission. Exiting.\n");
        exit(EXIT_FAILURE);
    } else {
        if (self.verbose) {
            fprintf(stderr, "Granting permission for automatic update checks with sending system profile %s...\n", self.updatePermissionResponse.sendSystemProfile ? "enabled" : "disabled");
        }
        reply(self.updatePermissionResponse);
    }
}

- (void)showUserInitiatedUpdateCheckWithCompletion:(void (^)(SPUUserInitiatedCheckStatus))updateCheckStatusCompletion
{
    [self.coreComponent registerUpdateCheckStatusHandler:updateCheckStatusCompletion];
    if (self.verbose) {
        fprintf(stderr, "Checking for Updates...\n");
    }
}

- (void)dismissUserInitiatedUpdateCheck
{
    [self.coreComponent completeUpdateCheckStatus];
}

- (void)displayReleaseNotes:(const char * _Nullable)releaseNotes
{
    if (releaseNotes != NULL) {
        fprintf(stderr, "Release notes:\n");
        fprintf(stderr, "%s\n", releaseNotes);
    }
}

- (void)displayHTMLReleaseNotes:(NSData *)releaseNotes
{
    // Note: this is the only API we rely on here that references AppKit
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithHTML:releaseNotes documentAttributes:nil];
    [self displayReleaseNotes:attributedString.string.UTF8String];
}

- (void)displayPlainTextReleaseNotes:(NSData *)releaseNotes encoding:(NSStringEncoding)encoding
{
    NSString *string = [[NSString alloc] initWithData:releaseNotes encoding:encoding];
    [self displayReleaseNotes:string.UTF8String];
}

- (void)showUpdateWithAppcastItem:(SUAppcastItem *)appcastItem updateAdjective:(NSString *)updateAdjective
{
    if (self.verbose) {
        fprintf(stderr, "Found %s update! (%s)\n", updateAdjective.UTF8String, appcastItem.displayVersionString.UTF8String);
        
        if (appcastItem.itemDescription != nil) {
            NSData *descriptionData = [appcastItem.itemDescription dataUsingEncoding:NSUTF8StringEncoding];
            if (descriptionData != nil) {
                [self displayHTMLReleaseNotes:descriptionData];
            }
        }
    }
}

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem userInitiated:(BOOL)__unused userInitiated reply:(void (^)(SPUUpdateAlertChoice))reply
{
    [self showUpdateWithAppcastItem:appcastItem updateAdjective:@"new"];
    reply(SPUInstallUpdateChoice);
}

- (void)showDownloadedUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem userInitiated:(BOOL)__unused userInitiated reply:(void (^)(SPUUpdateAlertChoice))reply
{
    [self showUpdateWithAppcastItem:appcastItem updateAdjective:@"downloaded"];
    reply(SPUInstallUpdateChoice);
}

- (void)showResumableUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem userInitiated:(BOOL)__unused userInitiated reply:(void (^)(SPUInstallUpdateStatus))reply
{
    [self.coreComponent registerInstallUpdateHandler:reply];
    [self showUpdateWithAppcastItem:appcastItem updateAdjective:@"resumable"];
    
    if (self.deferInstallation) {
        if (self.verbose) {
            fprintf(stderr, "Deferring Installation.\n");
        }
        [self.coreComponent installUpdateWithChoice:SPUDismissUpdateInstallation];
    } else {
        [self.coreComponent installUpdateWithChoice:SPUInstallAndRelaunchUpdateNow];
    }
}

- (void)showInformationalUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem userInitiated:(BOOL)__unused userInitiated reply:(void (^)(SPUInformationalUpdateAlertChoice))reply
{
    fprintf(stderr, "Found information for new update: %s\n", appcastItem.infoURL.absoluteString.UTF8String);
    
    reply(SPUDismissInformationalNoticeChoice);
}

- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData
{
    if (self.verbose) {
        if (downloadData.MIMEType != nil && [downloadData.MIMEType isEqualToString:@"text/plain"]) {
            NSStringEncoding encoding;
            if (downloadData.textEncodingName == nil) {
                encoding = NSUTF8StringEncoding;
            } else {
                CFStringEncoding cfEncoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef)downloadData.textEncodingName);
                if (cfEncoding != kCFStringEncodingInvalidId) {
                    encoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding);
                } else {
                    encoding = NSUTF8StringEncoding;
                }
            }
            [self displayPlainTextReleaseNotes:downloadData.data encoding:encoding];
        } else {
            [self displayHTMLReleaseNotes:downloadData.data];
        }
    }
}

- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error
{
    if (self.verbose) {
        fprintf(stderr, "Error: Unable to download release notes: %s\n", error.localizedDescription.UTF8String);
    }
}

- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))__unused acknowledgement __attribute__((noreturn))
{
    if (self.verbose) {
        fprintf(stderr, "No new update available!\n");
    }
    exit(EXIT_SUCCESS);
}

- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))__unused acknowledgement __attribute__((noreturn))
{
    fprintf(stderr, "Error: Update has failed: %s\n", error.localizedDescription.UTF8String);
    exit(EXIT_FAILURE);
}

- (void)showDownloadInitiatedWithCompletion:(void (^)(SPUDownloadUpdateStatus))downloadUpdateStatusCompletion
{
    [self.coreComponent registerDownloadStatusHandler:downloadUpdateStatusCompletion];
    
    if (self.verbose) {
        fprintf(stderr, "Downloading Update...\n");
    }
}

- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)expectedContentLength
{
    if (self.verbose) {
        fprintf(stderr, "Downloading %llu bytes...\n", expectedContentLength);
    }
    self.bytesDownloaded = 0;
    self.bytesToDownload = expectedContentLength;
}

- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length
{
    self.bytesDownloaded += length;
    
    // In case our expected content length was incorrect
    if (self.bytesDownloaded > self.bytesToDownload) {
        self.bytesToDownload = self.bytesDownloaded;
    }
    
    if (self.bytesToDownload > 0 && self.verbose) {
        fprintf(stderr, "Downloaded %llu out of %llu bytes (%.0f%%)\n", self.bytesDownloaded, self.bytesToDownload, (self.bytesDownloaded * 100.0 / self.bytesToDownload));
    }
}

- (void)showDownloadDidStartExtractingUpdate
{
    [self.coreComponent completeDownloadStatus];
    
    if (self.verbose) {
        fprintf(stderr, "Extracting update...\n");
    }
}

- (void)showExtractionReceivedProgress:(double)progress
{
    if (self.verbose) {
        fprintf(stderr, "Extracting Update (%.0f%%)\n", progress * 100);
    }
}

- (void)showReadyToInstallAndRelaunch:(void (^)(SPUInstallUpdateStatus))installUpdateHandler
{
    [self.coreComponent registerInstallUpdateHandler:installUpdateHandler];
    
    if (self.deferInstallation) {
        if (self.verbose) {
            fprintf(stderr, "Deferring Installation.\n");
        }
        [self.coreComponent installUpdateWithChoice:SPUDismissUpdateInstallation];
    } else {
        [self.coreComponent installUpdateWithChoice:SPUInstallAndRelaunchUpdateNow];
    }
}

- (void)showInstallingUpdate
{
    if (self.verbose) {
        fprintf(stderr, "Installing Update...\n");
    }
}

- (void)showUpdateInstallationDidFinishWithAcknowledgement:(void (^)(void))acknowledgement
{
    [self.coreComponent registerAcknowledgement:acknowledgement];
    
    if (self.verbose) {
       fprintf(stderr, "Installation Finished.\n");
    }
    
    [self.coreComponent acceptAcknowledgement];
}

- (void)dismissUpdateInstallation __attribute__((noreturn))
{
    if (self.verbose) {
        fprintf(stderr, "Exiting.\n");
    }
    exit(EXIT_SUCCESS);
}

- (void)showSendingTerminationSignal
{
    // We are already showing that the update is installing, so there is no need to do anything here
}

@end
