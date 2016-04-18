//
//  SUUpdateDownloader.m
//  UpdateDownloader
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUpdateDownloader.h"
#import "SUDownloaderDelegate.h"
#import "SUErrors.h"

@interface SUUpdateDownloader () <NSURLDownloadDelegate>

@property (nonatomic) id <SUDownloaderDelegate> delegate;
@property (nonatomic) NSURLDownload *download;
@property (nonatomic, copy) NSString *bundleIdentifier;
@property (nonatomic, copy) NSString *desiredFilename;
@property (nonatomic, copy) void (^completionBlock)(BOOL, NSError * _Nullable);

@end

@implementation SUUpdateDownloader

@synthesize delegate = _delegate;
@synthesize download = _download;
@synthesize bundleIdentifier = _bundleIdentifier;
@synthesize desiredFilename = _desiredFilename;
@synthesize completionBlock = _completionBlock;

- (instancetype)initWithDelegate:(id <SUDownloaderDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

- (void)dealloc
{
    [self cleanup];
}

- (void)startDownloadWithRequest:(NSURLRequest *)request bundleIdentifier:(NSString *)bundleIdentifier desiredFilename:(NSString *)desiredFilename completion:(void (^)(BOOL success, NSError * _Nullable error))completionBlock
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.download = [[NSURLDownload alloc] initWithRequest:request delegate:self];
        self.desiredFilename = desiredFilename;
        self.bundleIdentifier = bundleIdentifier;
        self.completionBlock = completionBlock;
        
        // Remove our old caches path so we don't start accumulating files in there
        NSString *cachePath = [[self class] sparkleCachePathForBundleIdentifier:self.bundleIdentifier];
        if ([[NSFileManager defaultManager] fileExistsAtPath:cachePath]) {
            [[NSFileManager defaultManager] removeItemAtPath:cachePath error:NULL];
        }
    });
}

- (void)cleanup
{
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

// If we support sandboxing this component in the future, it is important to note this may return a different path
// For this reason, this method should not be a part of SUHost because its behavior depends on what kind of process it's being invoked from
+ (NSString *)sparkleCachePathForBundleIdentifier:(NSString *)bundleIdentifier
{
    NSURL *cacheURL = [[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:NULL];
    
    assert(cacheURL != nil);
    return [[[cacheURL URLByAppendingPathComponent:bundleIdentifier] URLByAppendingPathComponent:@"Sparkle"] path];
}

- (void)download:(NSURLDownload *)__unused d decideDestinationWithSuggestedFilename:(NSString *)name
{
    NSString *downloadFileName = self.desiredFilename;
    
    NSString *cachePath = [[self class] sparkleCachePathForBundleIdentifier:self.bundleIdentifier];
    
    NSString *tempDir = [cachePath stringByAppendingPathComponent:downloadFileName];
    int count = 1;
    while ([[NSFileManager defaultManager] fileExistsAtPath:tempDir] && count <= 999)
    {
        tempDir = [cachePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %d", downloadFileName, count++]];
    }
    
    // Create the temporary directory if necessary.
    BOOL success = [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:NULL];
    if (!success)
    {
        // Okay, something's really broken with this user's file structure.
        [self.download cancel];
        self.download = nil;
        
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUTemporaryDirectoryError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Can't make a temporary directory for the update download at %@.", tempDir] }];
        
        [self.delegate downloaderDidFailToCreateTemporaryDirectoryWithError:error];
    } else {
        [self.download setDestination:[tempDir stringByAppendingPathComponent:name] allowOverwrite:YES];
        
        [self.delegate downloaderDidSetDestinationName:name temporaryDirectory:tempDir];
    }
}

- (void)download:(NSURLDownload *)__unused download didReceiveResponse:(NSURLResponse *)response
{
    [self.delegate downloaderDidReceiveResponse:response];
}

- (void)download:(NSURLDownload *)__unused download didReceiveDataOfLength:(NSUInteger)length
{
    [self.delegate downloaderDidReceiveDataOfLength:length];
}

- (void)downloadDidFinish:(NSURLDownload *)__unused d
{
    self.download = nil;
    self.completionBlock(YES, nil);
    self.completionBlock = nil;
}

- (void)download:(NSURLDownload *)__unused download didFailWithError:(NSError *)error
{
    self.download = nil;
    self.completionBlock(NO, error);
    self.completionBlock = nil;
}

- (BOOL)download:(NSURLDownload *)__unused download shouldDecodeSourceDataOfMIMEType:(NSString *)encodingType
{
    // We don't want the download system to extract our gzips.
    // Note that we use a substring matching here instead of direct comparison because the docs say "application/gzip" but the system *uses* "application/x-gzip". This is a documentation bug.
    return ([encodingType rangeOfString:@"gzip"].location == NSNotFound);
}

@end
