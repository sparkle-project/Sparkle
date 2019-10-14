//
//  SPUDownloaderSession.m
//  Sparkle
//
//  Created by Deadpikle on 12/20/17.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import "SPUDownloaderSession.h"
#import "SPUURLRequest.h"
#import "SPUDownloader_Private.h"
#import "SPULocalCacheDirectory.h"
#import "SUErrors.h"
#import "SPUDownloadData.h"

#include "AppKitPrevention.h"

@interface SPUDownloaderSession () <NSURLSessionDelegate>

@property (nonatomic) NSURLSession *downloadSession;
@property (nonatomic) NSURLSessionDownloadTask *download;

@end

@implementation SPUDownloaderSession

@synthesize downloadSession = _downloadSession;
@synthesize download = _download;

- (void)startDownloadWithRequest:(SPUURLRequest *)request
{
    NSOperationQueue *queue = [NSOperationQueue mainQueue];
    self.downloadSession = [NSURLSession
                             sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                             delegate:self
                             delegateQueue:queue];
    self.download = [self.downloadSession downloadTaskWithRequest:request.request];
    [self.download resume];
}

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

- (void)URLSession:(NSURLSession *)__unused session downloadTask:(NSURLSessionDownloadTask *)__unused downloadTask didFinishDownloadingToURL:(NSURL *)location
{
    if (self.mode == SPUDownloadModeTemporary) {
        self.downloadFilename = location.path;
        [self downloadDidFinish]; // file is already in a system temp dir
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

- (void)URLSession:(NSURLSession *)__unused session task:(NSURLSessionTask *)__unused task didCompleteWithError:(NSError *)error
{
    self.download = nil;
    if (error) {
        [self.delegate downloaderDidFailWithError:error];
    }
    [self cleanup];
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
    
    [super downloadDidFinishWithData:downloadData];
}

-(void)cleanup
{
    [self.download cancel];
    [self.downloadSession invalidateAndCancel];
    self.download = nil;
    self.downloadSession = nil;
    [super cleanup];
}

- (void)cancel
{
    [self cleanup];
}

// NSURLDownload has a [downlaod:shouldDecodeSourceDataOfMIMEType:] to determine if the data should be decoded.
// This does not exist for NSURLSessionDownloadTask and appears unnecessary. Data tasks will decode data, but not download tasks.

@end
