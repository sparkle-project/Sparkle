//
//  SPUReleaseNotesDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUReleaseNotesDriver.h"
#import "SUHost.h"
#import "SUErrors.h"
#import "SPUDownloadData.h"
#import "SPUDownloadDataPrivate.h"
#import "SPUExtractSignedFeed.h"
#import "SUSignatures.h"
#import "SUSignatureVerifier.h"
#import "SPUVerifierInformation.h"
#import "SULocalizations.h"


#include "AppKitPrevention.h"

@implementation SPUReleaseNotesDriver
{
    SPUDownloadDriver *_downloadDriver;
    SUHost *_host;
    SUSignatures *_signatures;

    void (^_completionHandler)(SPUDownloadData * _Nullable, NSError  * _Nullable);

    uint64_t _contentLength;
}

- (instancetype)initWithReleaseNotesURL:(NSURL *)releaseNotesURL contentLength:(uint64_t)contentLength signatures:(SUSignatures * _Nullable)signatures httpHeaders:(NSDictionary * _Nullable)httpHeaders userAgent:(NSString * _Nullable)userAgent host:(SUHost *)host completionHandler:(void (^)(SPUDownloadData * _Nullable, NSError * _Nullable))completionHandler
{
    self = [super init];
    if (self != nil) {
        _host = host;
        _signatures = signatures;
        _contentLength = contentLength;
        _downloadDriver = [[SPUDownloadDriver alloc] initWithRequestURL:releaseNotesURL host:host userAgent:userAgent httpHeaders:httpHeaders inBackground:NO cachePolicy:NSURLRequestReloadIgnoringLocalCacheData delegate:self];
        _completionHandler = [completionHandler copy];
    } else {
        assert(false);
    }
    return self;
}

- (void)startDownload
{
    [_downloadDriver downloadFile];
}

- (void)downloadDriverDidDownloadData:(SPUDownloadData *)downloadDataToValidate
{
    if (_completionHandler != nil) {
        SPUDownloadData *downloadDataToPassToUserDriver;

        // Strip out any sign warning comment prefix for markdown data so that user drivers
        // will not have to deal with parsing them (if their markdown parsers don't handle decoding HTML)
        NSString *MIMEType = downloadDataToValidate.MIMEType;
        NSString *pathExtension = _downloadDriver.request.URL.pathExtension;
        if ([MIMEType isEqualToString:@"text/markdown"] || [MIMEType isEqualToString:@"text/x-markdown"] ||
            [pathExtension caseInsensitiveCompare:@"md"] == NSOrderedSame || [pathExtension caseInsensitiveCompare:@"markdown"] == NSOrderedSame) {

            NSData *contentData = SPUExtractReleaseNotesContent(downloadDataToValidate.data);
            if (contentData.length != downloadDataToValidate.data.length) {
                downloadDataToPassToUserDriver = [[SPUDownloadData alloc] initWithData:contentData URL:downloadDataToValidate.URL textEncodingName:downloadDataToValidate.textEncodingName MIMEType:downloadDataToValidate.MIMEType];
            } else {
                downloadDataToPassToUserDriver = downloadDataToValidate;
            }
        } else {
            downloadDataToPassToUserDriver = downloadDataToValidate;
        }

        if (_host.requiresSignedAppcast) {
            SUSignatureVerifier *signatureVerifier = [[SUSignatureVerifier alloc] initWithPublicKeys:_host.publicKeys];
            SPUVerifierInformation *verifierInformation = [[SPUVerifierInformation alloc] initWithExpectedVersion:nil expectedContentLength:_contentLength];
            verifierInformation.actualContentLength = downloadDataToValidate.data.length;

            NSError *verifierError = nil;
            if (![signatureVerifier verifyData:downloadDataToValidate.data signatures:_signatures fileKind:@"release notes" verifierInformation:verifierInformation error:&verifierError]) {
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{NSLocalizedDescriptionKey:SULocalizedStringFromTableInBundle(@"The release notes is improperly signed and could not be validated. Please contact the app developer for more information.", SPARKLE_TABLE, SUSparkleBundle(), nil)}];

                if (verifierError != nil) {
                    [userInfo setObject:verifierError forKey:NSUnderlyingErrorKey];
                }

                _completionHandler(nil, [NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:userInfo]);
            } else {
                _completionHandler(downloadDataToPassToUserDriver, nil);
            }
        } else {
            _completionHandler(downloadDataToPassToUserDriver, nil);
        }

        _completionHandler = nil;
    }
}

- (void)downloadDriverDidFailToDownloadFileWithError:(nonnull NSError *)error
{
    if (_completionHandler != nil) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{NSLocalizedDescriptionKey:SULocalizedStringFromTableInBundle(@"An error occurred while downloading the release notes.", SPARKLE_TABLE, SUSparkleBundle(), nil)}];

        if (error != nil) {
            [userInfo setObject:error forKey:NSUnderlyingErrorKey];
        }

        _completionHandler(nil, [NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:userInfo]);
        _completionHandler = nil;
    }
}

- (void)cleanup:(void (^)(void))cleanupHandler
{
    _completionHandler = nil;
    [_downloadDriver cleanup:cleanupHandler];
}

@end
