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
#import <Sparkle/SPUDownloadData.h>
#import <Sparkle/SUErrors.h>


#include "AppKitPrevention.h"

typedef NS_ENUM(NSUInteger, SPUDownloadMode)
{
    SPUDownloadModePersistent,
    SPUDownloadModeTemporary
};

static NSString *SUDownloadingReason = @"Downloading update related file";

@interface SPUDownloader () <NSURLSessionDownloadDelegate>

// Delegate is intentionally strongly referenced; see header
@property (nonatomic) id <SPUDownloaderDelegate> delegate;
@property (nonatomic) NSURLSessionDownloadTask *download;
@property (nonatomic) NSURLSession *downloadSession;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *desiredFilename;
@property (nonatomic, copy) NSString *downloadFilename;
@property (nonatomic) BOOL disabledAutomaticTermination;
@property (nonatomic) SPUDownloadMode mode;
@property (nonatomic) BOOL receivedExpectedBytes;

@end

@implementation SPUDownloader

@synthesize delegate = _delegate;
@synthesize download = _download;
@synthesize downloadSession = _downloadSession;
@synthesize bundleIdentifier = _bundleIdentifier;
@synthesize desiredFilename = _desiredFilename;
@synthesize downloadFilename = _downloadFilename;
@synthesize disabledAutomaticTermination = _disabledAutomaticTermination;
@synthesize mode = _mode;
@synthesize receivedExpectedBytes = _receivedExpectedBytes;

- (instancetype)initWithDelegate:(id <SPUDownloaderDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

- (void)startDownloadWithRequest:(SPUURLRequest *)request
{
    self.downloadSession = [NSURLSession
        sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
        delegate:self
        delegateQueue:[NSOperationQueue mainQueue]];
    self.download = [self.downloadSession downloadTaskWithRequest:request.request];
    [self.download resume];
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
            
            [self startDownloadWithRequest:request];
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
            [self startDownloadWithRequest:request];
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

- (void)cancelDownload
{
    [self cleanup];
}

- (void)cleanup
{
    [self enableAutomaticTermination];
    [self.download cancel];
    [self.downloadSession finishTasksAndInvalidate];
    self.download = nil;
    self.downloadSession = nil;
    self.delegate = nil;
    
    if (self.mode == SPUDownloadModeTemporary && self.downloadFilename != nil)
    {
        [[NSFileManager defaultManager] removeItemAtPath:self.downloadFilename error:NULL];
        self.downloadFilename = nil;
    }
}

- (void)URLSession:(NSURLSession *)__unused session downloadTask:(NSURLSessionDownloadTask *)__unused downloadTask didFinishDownloadingToURL:(NSURL *)location
{
    if (self.mode == SPUDownloadModeTemporary)
    {
        self.downloadFilename = location.path;
        [self downloadDidFinish]; // file is already in a system temp dir
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
                NSString *name = self.download.response.suggestedFilename;
                if (!name) {
                    name = location.lastPathComponent; // This likely contains nothing useful to identify the file (e.g. CFNetworkDownload_87LVIz.tmp)
                }
                NSString *toPath = [downloadFileNameDirectory stringByAppendingPathComponent:name];
                NSString *fromPath = location.path; // suppress moveItemAtPath: non-null warning
                NSError *error = nil;
                if ([[NSFileManager defaultManager] moveItemAtPath:fromPath toPath:toPath error:&error]) {
                    self.downloadFilename = toPath;
                    [self.delegate downloaderDidSetDestinationName:name temporaryDirectory:downloadFileNameDirectory];
                    [self downloadDidFinish];
                } else {
                    [self.delegate downloaderDidFailWithError:error];
                }
            }
        }
    }
}

- (void)URLSession:(NSURLSession *)__unused session downloadTask:(NSURLSessionDownloadTask *)__unused downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)__unused totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
        
    if (self.mode == SPUDownloadModePersistent && totalBytesExpectedToWrite > 0 && !self.receivedExpectedBytes) {
        self.receivedExpectedBytes = YES;
        [self.delegate downloaderDidReceiveExpectedContentLength:totalBytesExpectedToWrite];
    }
    
    if (self.mode == SPUDownloadModePersistent && bytesWritten >= 0) {
        [self.delegate downloaderDidReceiveDataOfLength:(uint64_t)bytesWritten];
    }
}

- (void)downloadDidFinish
{
    assert(self.downloadFilename != nil);
    
    SPUDownloadData *downloadData = nil;
    if (self.mode == SPUDownloadModeTemporary) {
        NSData *data = [NSData dataWithContentsOfFile:self.downloadFilename];
        if (data != nil) {
            NSURLResponse *response = self.download.response;
            assert(response != nil);
            downloadData = [[SPUDownloadData alloc] initWithData:data textEncodingName:response.textEncodingName MIMEType:response.MIMEType];
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

- (void)URLSession:(NSURLSession *)__unused session task:(NSURLSessionTask *)__unused task didCompleteWithError:(NSError *)error
{
    self.download = nil;
    [self.delegate downloaderDidFailWithError:error];
    [self cleanup];
}

// NSURLDownload has a [downlaod:shouldDecodeSourceDataOfMIMEType:] to determine if the data should be decoded.
// This does not exist for NSURLSessionDownloadTask and appears unnecessary. Data tasks will decode data, but not download tasks.

@end
