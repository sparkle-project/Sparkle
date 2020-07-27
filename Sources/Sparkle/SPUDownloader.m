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

@interface SPUDownloader ()

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

- (void)startPersistentDownloadWithRequest:(SPUURLRequest *)__unused request bundleIdentifier:(NSString *)__unused bundleIdentifier desiredFilename:(NSString *)__unused desiredFilename
{
    
}

- (void)startTemporaryDownloadWithRequest:(SPUURLRequest *)__unused request
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

- (void)cancel
{
    
}

- (void)downloadDidFinish
{
    
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

-(NSString*)getAndCleanTempDirectory
{
    NSString *rootPersistentDownloadCachePath = [[SPULocalCacheDirectory cachePathForBundleIdentifier:self.bundleIdentifier] stringByAppendingPathComponent:@"PersistentDownloads"];
    
    [SPULocalCacheDirectory removeOldItemsInDirectory:rootPersistentDownloadCachePath];
    
    NSString *tempDir = [SPULocalCacheDirectory createUniqueDirectoryInDirectory:rootPersistentDownloadCachePath];
    if (tempDir == nil) {
        // Okay, something's really broken with this user's file structure.
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUTemporaryDirectoryError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Can't make a temporary directory for the update download at %@.", tempDir] }];
        
        [self.delegate downloaderDidFailWithError:error];
        
        [self cancel];
    }
    return tempDir;
}

@end
