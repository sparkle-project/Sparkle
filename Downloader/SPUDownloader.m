//
//  SPUDownloader.m
//  Downloader
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUDownloader.h"
#import "SPUDownloaderDelegate.h"
#import "SPULocalCacheDirectory.h"
#import "SPUURLRequest.h"
#import "SPUDownloadData.h"
#import "SUErrors.h"


#include "AppKitPrevention.h"

typedef NS_ENUM(NSUInteger, SPUDownloadMode)
{
    SPUDownloadModePersistent,
    SPUDownloadModeTemporary
};

static NSString *SUDownloadingReason = @"Downloading update related file";

@interface SPUDownloader () <NSURLDownloadDelegate>

// Delegate is intentionally strongly referenced; see header
@property (nonatomic) id <SPUDownloaderDelegate> delegate;
@property (nonatomic) NSURLDownload *download;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *desiredFilename;
@property (nonatomic, copy) NSString *downloadFilename;
@property (nonatomic) BOOL disabledAutomaticTermination;
@property (nonatomic) SPUDownloadMode mode;
@property (nonatomic) NSURLResponse *response;

@end

@implementation SPUDownloader

@synthesize delegate = _delegate;
@synthesize download = _download;
@synthesize bundleIdentifier = _bundleIdentifier;
@synthesize desiredFilename = _desiredFilename;
@synthesize downloadFilename = _downloadFilename;
@synthesize disabledAutomaticTermination = _disabledAutomaticTermination;
@synthesize mode = _mode;
@synthesize response = _response;

- (instancetype)initWithDelegate:(id <SPUDownloaderDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

// Don't implement dealloc - make the client call cleanup, which is the only way to remove the reference cycle from the delegate anyway

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

- (void)enableAutomaticTermination
{
    if (self.disabledAutomaticTermination) {
        [[NSProcessInfo processInfo] enableAutomaticTermination:SUDownloadingReason];
        self.disabledAutomaticTermination = NO;
    }
}

- (void)cleanup
{
    [self enableAutomaticTermination];
    [self.download cancel];
    self.download = nil;
    self.delegate = nil;
    
    if (self.mode == SPUDownloadModeTemporary && self.downloadFilename != nil)
    {
        [[NSFileManager defaultManager] removeItemAtPath:self.downloadFilename error:NULL];
        self.downloadFilename = nil;
    }
}

- (void)download:(NSURLDownload *)__unused d decideDestinationWithSuggestedFilename:(NSString *)name
{
    if (self.mode == SPUDownloadModeTemporary)
    {
        // Files downloaded in temporary mode should not last for very long,
        // so it's ideal to place them in a system temporary directory
        NSString *destinationFilename = NSTemporaryDirectory();
        if (destinationFilename)
        {
            destinationFilename = [destinationFilename stringByAppendingPathComponent:name];
            
            [self.download setDestination:destinationFilename allowOverwrite:NO];
        }
    }
    else
    {
        // Remove our old caches path so we don't start accumulating files in there
        NSString *rootPersistentDownloadCachePath = [[SPULocalCacheDirectory cachePathForBundleIdentifier:self.bundleIdentifier] stringByAppendingPathComponent:@"PersistentDownloads"];
        
        [SPULocalCacheDirectory removeOldItemsInDirectory:rootPersistentDownloadCachePath];
        
        NSString *tempDir = [SPULocalCacheDirectory createUniqueDirectoryInDirectory:rootPersistentDownloadCachePath];
        if (tempDir == nil)
        {
            // Okay, something's really broken with this user's file structure.
            [self.download cancel];
            self.download = nil;
            
            NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUTemporaryDirectoryError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Can't make a temporary directory for the update download at %@.", tempDir] }];
            
            [self.delegate downloaderDidFailWithError:error];
        } else {
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
    
    switch (self.mode) {
        case SPUDownloadModeTemporary:
            if (downloadData != nil) {
                [self.delegate downloaderDidFinishWithTemporaryDownloadData:downloadData];
            } else {
                [self.delegate downloaderDidFailWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to read temporary downloaded data from %@", self.downloadFilename]}]];
            }
            break;
        case SPUDownloadModePersistent:
            [self.delegate downloaderDidFinishWithTemporaryDownloadData:nil];
            break;
    }
    
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

@end
