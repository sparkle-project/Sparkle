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
#import "SPUDownloader_Private.h"

#include "AppKitPrevention.h"

@interface SPUDownloader () <NSURLSessionDownloadDelegate>

@property (nonatomic) NSURLSession *downloadSession;

@end

@implementation SPUDownloader

@synthesize delegate = _delegate;
@synthesize download = _download;
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
}

- (void)startTemporaryDownloadWithRequest:(SPUURLRequest *)request
{
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
    self.downloadSession = nil;
    self.delegate = nil;
    
    if (self.mode == SPUDownloadModeTemporary && self.downloadFilename != nil)
    {
        [[NSFileManager defaultManager] removeItemAtPath:self.downloadFilename error:NULL];
        self.downloadFilename = nil;
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

@end
