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

@implementation SPUCommandLineUserDriver
{
    SUUpdatePermissionResponse *_updatePermissionResponse;
    NSString *_lastProgressReported;
    
    uint64_t _bytesDownloaded;
    uint64_t _bytesToDownload;
    
    BOOL _deferInstallation;
    BOOL _verbose;
}

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
    if (_verbose) {
        fprintf(stderr, "Granting permission for automatic update checks with sending system profile %s...\n", _updatePermissionResponse.sendSystemProfile ? "enabled" : "disabled");
    }
    reply(_updatePermissionResponse);
}

- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))__unused cancellation
{
    if (_verbose) {
        fprintf(stderr, "Checking for Updates...\n");
    }
}

- (void)displayReleaseNotes:(const char * _Nullable)releaseNotes SPU_OBJC_DIRECT
{
    if (releaseNotes != NULL) {
        fprintf(stderr, "Release notes:\n");
        fprintf(stderr, "%s\n", releaseNotes);
    }
}

- (void)displayHTMLReleaseNotes:(NSData *)releaseNotes SPU_OBJC_DIRECT
{
    // Note: this is the only API we rely on here that references AppKit
    // We shouldn't invoke it when the calling process is ran under root.
    // If only there was an API to translated HTML -> text that didn't rely on AppKit..
    if (geteuid() != 0) {
        NSAttributedString *attributedString = [[NSAttributedString alloc] initWithHTML:releaseNotes documentAttributes:nil];
        [self displayReleaseNotes:attributedString.string.UTF8String];
    }
}

- (void)displayPlainTextReleaseNotes:(NSData *)releaseNotes encoding:(NSStringEncoding)encoding SPU_OBJC_DIRECT
{
    NSString *string = [[NSString alloc] initWithData:releaseNotes encoding:encoding];
    [self displayReleaseNotes:string.UTF8String];
}

- (void)showUpdateWithAppcastItem:(SUAppcastItem *)appcastItem updateAdjective:(NSString *)updateAdjective
{
    if (_verbose) {
        fprintf(stderr, "Found %s update! (%s)\n", updateAdjective.UTF8String, appcastItem.displayVersionString.UTF8String);
        
        if (appcastItem.itemDescription != nil) {
            NSData *descriptionData = [appcastItem.itemDescription dataUsingEncoding:NSUTF8StringEncoding];
            if (descriptionData != nil) {
                NSString *itemDescriptionFormat = appcastItem.itemDescriptionFormat;
                if (itemDescriptionFormat != nil && [itemDescriptionFormat isEqualToString:@"plain-text"]) {
                    [self displayPlainTextReleaseNotes:descriptionData encoding:NSUTF8StringEncoding];
                } else {
                    [self displayHTMLReleaseNotes:descriptionData];
                }
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
                if (_deferInstallation) {
                    if (_verbose) {
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

- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData
{
    if (_verbose) {
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
    if (_verbose) {
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
    if (_verbose) {
        _lastProgressReported = nil;
        fprintf(stderr, "Downloading Update...\n");
    }
}

- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)expectedContentLength
{
    if (_verbose) {
        fprintf(stderr, "Downloading %llu bytes...\n", expectedContentLength);
    }
    _bytesDownloaded = 0;
    _bytesToDownload = expectedContentLength;
}

- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length
{
    _bytesDownloaded += length;
    
    // In case our expected content length was incorrect
    if (_bytesDownloaded > _bytesToDownload) {
        _bytesToDownload = _bytesDownloaded;
    }
    
    if (_bytesToDownload > 0 && _verbose) {
        NSString *currentProgressPercentage = [NSString stringWithFormat:@"%.0f%%", (_bytesDownloaded * 100.0 / _bytesToDownload)];
        
        // Only report progress advancement when percentage significantly advances
        if (_lastProgressReported == nil || ![_lastProgressReported isEqualToString:currentProgressPercentage]) {
            fprintf(stderr, "Downloaded %llu out of %llu bytes (%s)\n", _bytesDownloaded, _bytesToDownload, currentProgressPercentage.UTF8String);
            
            _lastProgressReported = currentProgressPercentage;
        }
    }
}

- (void)showDownloadDidStartExtractingUpdate
{
    if (_verbose) {
        _lastProgressReported = nil;
        fprintf(stderr, "Extracting Update...\n");
    }
}

- (void)showExtractionReceivedProgress:(double)progress
{
    if (_verbose) {
        NSString *currentProgressPercentage = [NSString stringWithFormat:@"%.0f%%", progress * 100];
        
        // Only report progress advancement when percentage significantly advances
        if (_lastProgressReported == nil || ![_lastProgressReported isEqualToString:currentProgressPercentage]) {
            fprintf(stderr, "Extracting Update (%s)\n", currentProgressPercentage.UTF8String);
            
            _lastProgressReported = currentProgressPercentage;
        }
    }
}

- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))installUpdateHandler
{
    if (_deferInstallation) {
        if (_verbose) {
            fprintf(stderr, "Deferring Installation.\n");
        }
        installUpdateHandler(SPUUserUpdateChoiceDismiss);
    } else {
        installUpdateHandler(SPUUserUpdateChoiceInstall);
    }
}

- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)__unused applicationTerminated retryTerminatingApplication:(void (^)(void))__unused retryTerminatingApplication
{
    if (_verbose) {
        fprintf(stderr, "Installing Update...\n");
    }
}

- (void)showUpdateInstalledAndRelaunched:(BOOL)__unused relaunched acknowledgement:(void (^)(void))acknowledgement
{
    if (_verbose) {
       fprintf(stderr, "Installation Finished.\n");
    }
    
    acknowledgement();
}

- (void)dismissUpdateInstallation
{
}

@end
