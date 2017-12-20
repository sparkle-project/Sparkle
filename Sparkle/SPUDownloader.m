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

@end

@implementation SPUDownloader

@synthesize delegate = _delegate;
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
    self.delegate = nil;
    
    if (self.mode == SPUDownloadModeTemporary && self.downloadFilename != nil)
    {
        [[NSFileManager defaultManager] removeItemAtPath:self.downloadFilename error:NULL];
        self.downloadFilename = nil;
    }
}


-(void)downloadDidFinishWithData:(SPUDownloadData*)data
{
    switch (self.mode) {
        case SPUDownloadModeTemporary:
            if (data != nil) {
                [self.delegate downloaderDidFinishWithTemporaryDownloadData:data];
            } else {
                [self.delegate downloaderDidFailWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to read temporary downloaded data from %@", self.downloadFilename]}]];
            }
            break;
        case SPUDownloadModePersistent:
            [self.delegate downloaderDidFinishWithTemporaryDownloadData:nil];
            break;
    }
}

@end
