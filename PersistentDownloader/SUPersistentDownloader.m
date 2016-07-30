//
//  SUPersistentDownloader.m
//  PersistentDownloader
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUPersistentDownloader.h"
#import "SUPersistentDownloaderDelegate.h"
#import "SULocalCacheDirectory.h"
#import "SUURLRequest.h"
#import "SUErrors.h"

static NSString *SUPersistentDownloadingReason = @"Downloading persistent file";

@interface SUPersistentDownloader () <NSURLDownloadDelegate>

// Delegate is intentionally strongly referenced; see header
@property (nonatomic) id <SUPersistentDownloaderDelegate> delegate;
@property (nonatomic) NSURLDownload *download;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *desiredFilename;
@property (nonatomic) BOOL disabledAutomaticTermination;

@end

@implementation SUPersistentDownloader

@synthesize delegate = _delegate;
@synthesize download = _download;
@synthesize bundleIdentifier = _bundleIdentifier;
@synthesize desiredFilename = _desiredFilename;
@synthesize disabledAutomaticTermination = _disabledAutomaticTermination;

- (instancetype)initWithDelegate:(id <SUPersistentDownloaderDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

// Don't implement dealloc - make the client call cleanup, which is the only way to remove the reference cycle from the delegate anyway

- (void)startDownloadWithRequest:(SUURLRequest *)request bundleIdentifier:(NSString *)bundleIdentifier desiredFilename:(NSString *)desiredFilename
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // Prevent service from automatically terminating while downloading the update asynchronously without any reply blocks
        [[NSProcessInfo processInfo] disableAutomaticTermination:SUPersistentDownloadingReason];
        self.disabledAutomaticTermination = YES;
        
        self.download = [[NSURLDownload alloc] initWithRequest:request.request delegate:self];
        self.desiredFilename = desiredFilename;
        self.bundleIdentifier = bundleIdentifier;
    });
}

- (void)enableAutomaticTermination
{
    if (self.disabledAutomaticTermination) {
        [[NSProcessInfo processInfo] enableAutomaticTermination:SUPersistentDownloadingReason];
        self.disabledAutomaticTermination = NO;
    }
}

- (void)cleanup
{
    [self enableAutomaticTermination];
    [self.download cancel];
    self.download = nil;
    self.delegate = nil;
}

- (void)cleanupWithCompletion:(void (^)(void))completionBlock
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self cleanup];
        completionBlock();
    });
}

- (void)download:(NSURLDownload *)__unused d decideDestinationWithSuggestedFilename:(NSString *)name
{
    // Remove our old caches path so we don't start accumulating files in there
    NSString *rootPersistentDownloadCachePath = [[SULocalCacheDirectory cachePathForBundleIdentifier:self.bundleIdentifier] stringByAppendingPathComponent:@"PersistentDownloads"];
    
    [SULocalCacheDirectory removeOldItemsInDirectory:rootPersistentDownloadCachePath];
    
    NSString *tempDir = [SULocalCacheDirectory createUniqueDirectoryInDirectory:rootPersistentDownloadCachePath];
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

- (void)download:(NSURLDownload *)__unused download didReceiveResponse:(NSURLResponse *)response
{
    // It might be tempting to send over the response object instead of the expected content length but this isn't a good idea
    // For one, we are only ever concerned about the expected content length
    // Another reason is that NSURLResponse doesn't support NSSecureCoding in older OS releases (eg: 10.8), which cause issues with XPC
    [self.delegate downloaderDidReceiveExpectedContentLength:response.expectedContentLength];
}

- (void)download:(NSURLDownload *)__unused download didReceiveDataOfLength:(NSUInteger)length
{
    [self.delegate downloaderDidReceiveDataOfLength:length];
}

- (void)downloadDidFinish:(NSURLDownload *)__unused d
{
    self.download = nil;
    [self.delegate downloaderDidFinishDownloading];
}

- (void)download:(NSURLDownload *)__unused download didFailWithError:(NSError *)error
{
    self.download = nil;
    [self.delegate downloaderDidFailWithError:error];
}

- (BOOL)download:(NSURLDownload *)__unused download shouldDecodeSourceDataOfMIMEType:(NSString *)encodingType
{
    // We don't want the download system to extract our gzips.
    // Note that we use a substring matching here instead of direct comparison because the docs say "application/gzip" but the system *uses* "application/x-gzip". This is a documentation bug.
    return ([encodingType rangeOfString:@"gzip"].location == NSNotFound);
}

@end
