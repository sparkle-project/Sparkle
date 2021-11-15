//
//  SUCommandLineUserDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUCommandLineUserDriver.h"
#import <AppKit/AppKit.h>
#import <Sparkle/Sparkle.h>

@interface SPUCommandLineUserDriver ()

@property (nonatomic, nullable, readonly) SUUpdatePermissionResponse *updatePermissionResponse;
@property (nonatomic, readonly) BOOL deferInstallation;
@property (nonatomic, readonly) BOOL verbose;
@property (nonatomic) uint64_t bytesDownloaded;
@property (nonatomic) uint64_t bytesToDownload;

@end

@implementation SPUCommandLineUserDriver

@synthesize updatePermissionResponse = _updatePermissionResponse;
@synthesize deferInstallation = _deferInstallation;
@synthesize verbose = _verbose;
@synthesize bytesDownloaded = _bytesDownloaded;
@synthesize bytesToDownload = _bytesToDownload;

- (instancetype)initWithUpdatePermissionResponse:(nullable SUUpdatePermissionResponse *)updatePermissionResponse deferInstallation:(BOOL)deferInstallation verbose:(BOOL)verbose
{
    self = [super init];
    if (self != nil) {
        _updatePermissionResponse = updatePermissionResponse;
        _deferInstallation = deferInstallation;
        _verbose = verbose;
    }
    return self;
}

- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)__unused request reply:(void (^)(SUUpdatePermissionResponse *))reply
{
    if (self.verbose) {
        fprintf(stderr, "Granting permission for automatic update checks with sending system profile %s...\n", self.updatePermissionResponse.sendSystemProfile ? "enabled" : "disabled");
    }
    reply(self.updatePermissionResponse);
}

- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))__unused cancellation
{
    if (self.verbose) {
        fprintf(stderr, "Checking for Updates...\n");
    }
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

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply
{
    if (appcastItem.informationOnlyUpdate) {
        fprintf(stderr, "Found information for new update: %s\n", appcastItem.infoURL.absoluteString.UTF8String);
        reply(SPUUserUpdateChoiceDismiss);
    } else {
        switch (state.stage) {
            case SPUUserUpdateStageNotDownloaded:
                [self showUpdateWithAppcastItem:appcastItem updateAdjective:@"new"];
                reply(SPUUserUpdateChoiceInstall);
                break;
            case SPUUserUpdateStageDownloaded:
                [self showUpdateWithAppcastItem:appcastItem updateAdjective:@"downloaded"];
                reply(SPUUserUpdateChoiceInstall);
                break;
            case SPUUserUpdateStageInstalling:
                if (self.deferInstallation) {
                    if (self.verbose) {
                        fprintf(stderr, "Deferring Installation.\n");
                    }
                    reply(SPUUserUpdateChoiceDismiss);
                } else {
                    reply(SPUUserUpdateChoiceInstall);
                }
                break;
        }
    }
}

- (void)showUpdateInFocus
{
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

- (void)showUpdateNotFoundWithError:(NSError *)__unused error acknowledgement:(void (^)(void))acknowledgement
{
    acknowledgement();
}

- (void)showUpdaterError:(NSError *)__unused error acknowledgement:(void (^)(void))acknowledgement
{
    acknowledgement();
}

- (void)showDownloadInitiatedWithCancellation:(void (^)(void))__unused cancellation
{
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
    if (self.verbose) {
        fprintf(stderr, "Extracting Update...\n");
    }
}

- (void)showExtractionReceivedProgress:(double)progress
{
    if (self.verbose) {
        fprintf(stderr, "Extracting Update (%.0f%%)\n", progress * 100);
    }
}

- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))installUpdateHandler
{
    if (self.deferInstallation) {
        if (self.verbose) {
            fprintf(stderr, "Deferring Installation.\n");
        }
        installUpdateHandler(SPUUserUpdateChoiceDismiss);
    } else {
        installUpdateHandler(SPUUserUpdateChoiceInstall);
    }
}

- (void)showInstallingUpdate
{
    if (self.verbose) {
        fprintf(stderr, "Installing Update...\n");
    }
}

- (void)showUpdateInstalledAndRelaunched:(BOOL)__unused relaunched acknowledgement:(void (^)(void))acknowledgement
{
    if (self.verbose) {
       fprintf(stderr, "Installation Finished.\n");
    }
    
    acknowledgement();
}

- (void)dismissUpdateInstallation
{
}

- (void)showSendingTerminationSignal
{
    // We are already showing that the update is installing, so there is no need to do anything here
}

@end
