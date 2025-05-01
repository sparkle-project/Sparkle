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
#import "SPUDownloadData.h"
#import "SPUDownloadDataPrivate.h"
#import "SUErrors.h"


#include "AppKitPrevention.h"

typedef NS_ENUM(NSUInteger, SPUDownloadMode)
{
    SPUDownloadModePersistent,
    SPUDownloadModeTemporary
};

static NSString *SUDownloadingReason = @"Downloading update related file";

@interface SPUDownloader () <NSURLSessionDownloadDelegate>
@end

@implementation SPUDownloader
{
    NSURLSessionDownloadTask *_download;
    NSURLSession *_downloadSession;
    NSString *_bundleIdentifier;
    NSString *_desiredFilename;
    NSString *_downloadFilename;
    
    // Delegate is intentionally strongly referenced; see header
    id <SPUDownloaderDelegate> _delegate;
    
    SPUDownloadMode _mode;
    
    BOOL _disabledAutomaticTermination;
    BOOL _receivedExpectedBytes;
}

- (instancetype)initWithDelegate:(id <SPUDownloaderDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

- (void)startDownloadWithRequest:(NSURLRequest *)request SPU_OBJC_DIRECT
{
    _downloadSession = [NSURLSession
        sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
        delegate:self
        delegateQueue:[NSOperationQueue mainQueue]];
    _download = [_downloadSession downloadTaskWithRequest:request];
    [_download resume];
}

// Don't implement dealloc - make the client call cleanup, which is the only way to remove the reference cycle from the delegate anyway

- (void)startPersistentDownloadWithRequest:(NSURLRequest *)request bundleIdentifier:(NSString *)bundleIdentifier desiredFilename:(NSString *)desiredFilename
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_download == nil && self->_delegate != nil) {
            // Prevent service from automatically terminating while downloading the update asynchronously without any reply blocks
            [[NSProcessInfo processInfo] disableAutomaticTermination:SUDownloadingReason];
            self->_disabledAutomaticTermination = YES;
            
            self->_mode = SPUDownloadModePersistent;
            self->_desiredFilename = desiredFilename;
            self->_bundleIdentifier = [bundleIdentifier copy];
            
            [self startDownloadWithRequest:request];
        }
    });
}

- (void)startTemporaryDownloadWithRequest:(NSURLRequest *)request
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_download == nil && self->_delegate != nil) {
            // Prevent service from automatically terminating while downloading the update asynchronously without any reply blocks
            [[NSProcessInfo processInfo] disableAutomaticTermination:SUDownloadingReason];
            self->_disabledAutomaticTermination = YES;
            
            self->_mode = SPUDownloadModeTemporary;
            [self startDownloadWithRequest:request];
        }
    });
}

- (void)enableAutomaticTermination SPU_OBJC_DIRECT
{
    if (_disabledAutomaticTermination) {
        [[NSProcessInfo processInfo] enableAutomaticTermination:SUDownloadingReason];
        _disabledAutomaticTermination = NO;
    }
}

- (NSString *)rootPersistentDownloadCachePathForBundleIdentifier:(NSString *)bundleIdentifier SPU_OBJC_DIRECT
{
    // Note: The installer verifies this "PersistentDownloads" path component
    return [[SPULocalCacheDirectory cachePathForBundleIdentifier:bundleIdentifier] stringByAppendingPathComponent:@"PersistentDownloads"];
}

- (void)removeDownloadDirectoryWithDownloadToken:(NSString *)downloadToken bundleIdentifier:(NSString *)bundleIdentifier
{
    // Only take the directory name (from the download token) and compute most of the base path ourselves
    // This way we do not have to send/trust an absolute path
    // The downloader instance that creates this temp directory isn't necessarily the same as the one
    // that clears it (eg upon skipping an already downloaded update), so we can't just preserve it here too
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *rootPersistentDownloadCachePath = [self rootPersistentDownloadCachePathForBundleIdentifier:bundleIdentifier];
        if (rootPersistentDownloadCachePath != nil) {
            NSString *sanitizedDownloadToken = downloadToken.lastPathComponent;
            NSString *tempDir = [rootPersistentDownloadCachePath stringByAppendingPathComponent:sanitizedDownloadToken];
            
            [[NSFileManager defaultManager] removeItemAtPath:tempDir error:NULL];
        }
    });
}

- (void)_cleanup SPU_OBJC_DIRECT
{
    [self enableAutomaticTermination];
    [_download cancel];
    [_downloadSession finishTasksAndInvalidate];
    _download = nil;
    _downloadSession = nil;
    _delegate = nil;
    
    if (_mode == SPUDownloadModeTemporary && _downloadFilename != nil)
    {
        [[NSFileManager defaultManager] removeItemAtPath:_downloadFilename error:NULL];
        _downloadFilename = nil;
    }
}

- (void)cleanup:(void (^)(void))completionHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _cleanup];
        
        completionHandler();
    });
}

- (void)URLSession:(NSURLSession *)__unused session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location
{
    NSInteger statusCode = [downloadTask.response isKindOfClass:[NSHTTPURLResponse class]] ? ((NSHTTPURLResponse *)downloadTask.response).statusCode : 200;
    if ((statusCode < 200) || (statusCode >= 400))
    {
        NSString *message = [NSString stringWithFormat:@"A network error occurred while downloading %@. %@ (%ld)", downloadTask.originalRequest.URL.absoluteString, [NSHTTPURLResponse localizedStringForStatusCode:statusCode], (long)statusCode];
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:@{ NSLocalizedDescriptionKey: message }];
        [_delegate downloaderDidFailWithError:error];
    }
    else if (_mode == SPUDownloadModeTemporary)
    {
        _downloadFilename = location.path;
        [self downloadDidFinish]; // file is already in a system temp dir
    }
    else
    {
        // Remove our old caches path so we don't start accumulating files in there
        NSString *rootPersistentDownloadCachePath = [self rootPersistentDownloadCachePathForBundleIdentifier:_bundleIdentifier];

        [SPULocalCacheDirectory removeOldItemsInDirectory:rootPersistentDownloadCachePath];
        
        NSString *tempDir = [SPULocalCacheDirectory createUniqueDirectoryInDirectory:rootPersistentDownloadCachePath];
        if (tempDir == nil)
        {
            // Okay, something's really broken with this user's file structure.
            [_download cancel];
            _download = nil;
            
            NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUTemporaryDirectoryError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Can't make a temporary directory for the update download at %@.", tempDir] }];
            
            [_delegate downloaderDidFailWithError:error];
        } else {
            NSString *downloadFileName = _desiredFilename;
            NSString *downloadFileNameDirectory = [tempDir stringByAppendingPathComponent:downloadFileName];
            
            NSError *createError = nil;
            if (![[NSFileManager defaultManager] createDirectoryAtPath:downloadFileNameDirectory withIntermediateDirectories:NO attributes:nil error:&createError]) {
                NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUTemporaryDirectoryError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Can't make a download file name %@ directory inside temporary directory for the update download at %@.", downloadFileName, downloadFileNameDirectory] }];
                
                [_delegate downloaderDidFailWithError:error];
            } else {
                NSString *name = _download.response.suggestedFilename;
                if (!name) {
                    name = location.lastPathComponent; // This likely contains nothing useful to identify the file (e.g. CFNetworkDownload_87LVIz.tmp)
                }
                NSString *toPath = [downloadFileNameDirectory stringByAppendingPathComponent:name];
                NSString *fromPath = location.path; // suppress moveItemAtPath: non-null warning
                NSError *error = nil;
                if ([[NSFileManager defaultManager] moveItemAtPath:fromPath toPath:toPath error:&error]) {
                    _downloadFilename = toPath;
                    
                    // Create a bookmark for the download
                    // Don't pass any options (we don't want a persistent security scoped bookmark)
                    
                    NSURL *downloadURL = [NSURL fileURLWithPath:toPath isDirectory:NO];
                    
                    NSError *bookmarkError = nil;
                    NSData *bookmarkData = [downloadURL bookmarkDataWithOptions:0 includingResourceValuesForKeys:@[] relativeToURL:nil error:&bookmarkError];
                    if (bookmarkData == nil) {
                        [_delegate downloaderDidFailWithError:bookmarkError];
                    } else {
                        // The download token may be provided later to the downloader for removing a download
                        // and its temporary directory
                        NSString *downloadToken = tempDir.lastPathComponent;
                        [_delegate downloaderDidSetDownloadBookmarkData:bookmarkData downloadToken:downloadToken];
                        [self downloadDidFinish];
                    }
                } else {
                    [_delegate downloaderDidFailWithError:error];
                }
            }
        }
    }
}

- (void)URLSession:(NSURLSession *)__unused session downloadTask:(NSURLSessionDownloadTask *)__unused downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)__unused totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite
{
        
    if (_mode == SPUDownloadModePersistent && totalBytesExpectedToWrite > 0 && !_receivedExpectedBytes) {
        _receivedExpectedBytes = YES;
        [_delegate downloaderDidReceiveExpectedContentLength:totalBytesExpectedToWrite];
    }
    
    if (_mode == SPUDownloadModePersistent && bytesWritten >= 0) {
        [_delegate downloaderDidReceiveDataOfLength:(uint64_t)bytesWritten];
    }
}

- (void)downloadDidFinish SPU_OBJC_DIRECT
{
    assert(_downloadFilename != nil);
    
    SPUDownloadData *downloadData = nil;
    if (_mode == SPUDownloadModeTemporary) {
        NSData *data = [NSData dataWithContentsOfFile:_downloadFilename];
        if (data != nil) {
            NSURLResponse *response = _download.response;

            NSURL *responseURL = response.URL;
            if (responseURL == nil) {
                responseURL = _download.currentRequest.URL;
            }
            if (responseURL == nil) {
                responseURL = _download.originalRequest.URL;
            }
            assert(responseURL != nil);

            downloadData = [[SPUDownloadData alloc] initWithData:data URL:responseURL textEncodingName:response.textEncodingName MIMEType:response.MIMEType];
        }
    }
    
    _download = nil;
    
    switch (_mode) {
        case SPUDownloadModeTemporary:
            if (downloadData != nil) {
                [_delegate downloaderDidFinishWithTemporaryDownloadData:downloadData];
            } else {
                [_delegate downloaderDidFailWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to read temporary downloaded data from %@", _downloadFilename]}]];
            }
            
            [self _cleanup];
            break;
        case SPUDownloadModePersistent:
            [_delegate downloaderDidFinishWithTemporaryDownloadData:nil];
            break;
    }
}

- (void)URLSession:(NSURLSession *)__unused session task:(NSURLSessionTask *)__unused task didCompleteWithError:(NSError *)error
{
    _download = nil;
    if (error != nil) {
        [_delegate downloaderDidFailWithError:error];
    }
}

// NSURLDownload has a [download:shouldDecodeSourceDataOfMIMEType:] to determine if the data should be decoded.
// This does not exist for NSURLSessionDownloadTask and appears unnecessary. Data tasks will decode data, but not download tasks.

@end
