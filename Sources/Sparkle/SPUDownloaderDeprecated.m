//
//  SPUDownloaderDeprecated.m
//  Sparkle
//
//  Created by Deadpikle on 12/20/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import "SPUDownloaderDeprecated.h"
#import "SPUURLRequest.h"
#import "SPUDownloader_Private.h"
#import "SPUDownloadData.h"
#import "SPULocalCacheDirectory.h"
#import "SUErrors.h"

#include "AppKitPrevention.h"

@interface SPUDownloaderDeprecated () <NSURLDownloadDelegate>

@property (nonatomic) NSURLDownload *download;
@property (nonatomic) NSURLResponse *response;

@end

@implementation SPUDownloaderDeprecated

@synthesize download = _download;
@synthesize response = _response;

- (void)startPersistentDownloadWithRequest:(SPUURLRequest *)request bundleIdentifier:(NSString *)bundleIdentifier desiredFilename:(NSString *)desiredFilename
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.download == nil && self.delegate != nil) {
            // Prevent service from automatically terminating while downloading the update asynchronously without any reply blocks
            [[NSProcessInfo processInfo] disableAutomaticTermination:SUDownloadingReason];
            self.disabledAutomaticTermination = YES;
            
            self.mode = SPUDownloadModePersistent;
            self.desiredFilename = desiredFilename;
            self.bundleIdentifier = bundleIdentifier;
            
            self.download = [[NSURLDownload alloc] initWithRequest:request.request delegate:self];
        }
    });
}

- (void)startTemporaryDownloadWithRequest:(SPUURLRequest *)request
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.download == nil && self.delegate != nil) {
            // Prevent service from automatically terminating while downloading the update asynchronously without any reply blocks
            [[NSProcessInfo processInfo] disableAutomaticTermination:SUDownloadingReason];
            self.disabledAutomaticTermination = YES;
            
            self.mode = SPUDownloadModeTemporary;
            self.download = [[NSURLDownload alloc] initWithRequest:request.request delegate:self];
        }
    });
}

- (void)download:(NSURLDownload *)__unused d decideDestinationWithSuggestedFilename:(NSString *)name
{
    if (self.mode == SPUDownloadModeTemporary) {
        // Files downloaded in temporary mode should not last for very long,
        // so it's ideal to place them in a system temporary directory
        NSString *destinationFilename = NSTemporaryDirectory();
        if (destinationFilename) {
            destinationFilename = [destinationFilename stringByAppendingPathComponent:name];
            
            [self.download setDestination:destinationFilename allowOverwrite:NO];
        }
    } else {
        NSString *tempDir = [super getAndCleanTempDirectory];
        
        if (tempDir != nil) {
            NSString *downloadFileName = self.desiredFilename;
            NSString *downloadFileNameDirectory = [tempDir stringByAppendingPathComponent:downloadFileName];
            
            NSError *createError = nil;
            if (![[NSFileManager defaultManager] createDirectoryAtPath:downloadFileNameDirectory withIntermediateDirectories:NO attributes:nil error:&createError]) {
                NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUTemporaryDirectoryError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Can't make a download file name %@ directory inside temporary directory for the update download at %@.", downloadFileName, downloadFileNameDirectory] }];
                
                [self.delegate downloaderDidFailWithError:error];
            } else {
                [self.download setDestination:[downloadFileNameDirectory stringByAppendingPathComponent:name] allowOverwrite:YES];
                
                [self.delegate downloaderDidSetDestinationName:name temporaryDirectory:downloadFileNameDirectory];
            }
        }
    }
}

- (void)download:(NSURLDownload *)__unused aDownload didCreateDestination:(NSString *)path
{
    self.downloadFilename = path;
}

- (void)download:(NSURLDownload *)__unused download didReceiveResponse:(NSURLResponse *)response
{
    self.response = response;
    
    if (self.mode == SPUDownloadModePersistent) {
        // It might be tempting to send over the response object instead of the expected content length but this isn't a good idea
        // For one, we are only ever concerned about the expected content length
        // Another reason is that NSURLResponse doesn't support NSSecureCoding in older OS releases (eg: 10.8), which cause issues with XPC
        [self.delegate downloaderDidReceiveExpectedContentLength:response.expectedContentLength];
    }
}

- (void)download:(NSURLDownload *)__unused download didReceiveDataOfLength:(NSUInteger)length
{
    if (self.mode == SPUDownloadModePersistent) {
        [self.delegate downloaderDidReceiveDataOfLength:length];
    }
}

- (void)downloadDidFinish:(NSURLDownload *)__unused d
{
    [self downloadDidFinish];
    [self cleanup];
}

- (void)download:(NSURLDownload *)__unused download didFailWithError:(NSError *)error
{
    self.download = nil;
    [self.delegate downloaderDidFailWithError:error];
    [self cleanup];
}

- (BOOL)download:(NSURLDownload *)__unused download shouldDecodeSourceDataOfMIMEType:(NSString *)encodingType
{
    // We don't want the download system to extract our gzips for persistent downloads
    // Note that we use a substring matching here instead of direct comparison because the docs say "application/gzip" but the system *uses* "application/x-gzip". This is a documentation bug.
    return (self.mode == SPUDownloadModeTemporary || [encodingType rangeOfString:@"gzip"].location == NSNotFound);
}

- (void)downloadDidFinish
{
    assert(self.response != nil);
    assert(self.downloadFilename != nil);
    
    SPUDownloadData *downloadData = nil;
    if (self.mode == SPUDownloadModeTemporary) {
        NSData *data = [NSData dataWithContentsOfFile:self.downloadFilename];
        if (data != nil) {
            downloadData = [[SPUDownloadData alloc] initWithData:data textEncodingName:self.response.textEncodingName MIMEType:self.response.MIMEType];
        }
    }
    
    self.download = nil;
    
    [super downloadDidFinishWithData:downloadData];
}

-(void)cleanup
{
    [self.download cancel];
    self.download = nil;
    self.response = nil;
    [super cleanup];
}

- (void)cancel
{
    [self cleanup];
}

@end
