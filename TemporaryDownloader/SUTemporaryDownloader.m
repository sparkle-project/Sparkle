//
//  SUTemporaryDownloader.m
//  TemporaryDownloader
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUTemporaryDownloader.h"
#import "SPUURLRequest.h"

@interface SUTemporaryDownloader () <NSURLDownloadDelegate>

@property (nonatomic, copy) void (^completionBlock)(NSData * _Nullable data, NSError * _Nullable error);
@property (nonatomic) NSURLDownload *download;
@property (nonatomic, copy) NSString *downloadFilename;

@end

@implementation SUTemporaryDownloader

@synthesize completionBlock = _completionBlock;
@synthesize download = _download;
@synthesize downloadFilename = _downloadFilename;

- (void)startDownloadWithRequest:(SPUURLRequest *)request completion:(void (^)(NSData * _Nullable data, NSError * _Nullable error))completionBlock
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.completionBlock = completionBlock;
        
        self.download = [[NSURLDownload alloc] initWithRequest:request.request delegate:self];
    });
}

- (void)dealloc
{
    [self cleanup];
}

- (void)cleanup
{
    if (self.downloadFilename != nil) {
        [[NSFileManager defaultManager] removeItemAtPath:self.downloadFilename error:nil];
    }
    self.downloadFilename = nil;
}

- (void)download:(NSURLDownload *)__unused aDownload decideDestinationWithSuggestedFilename:(NSString *)filename
{
    NSString *destinationFilename = NSTemporaryDirectory();
    if (destinationFilename)
    {
        destinationFilename = [destinationFilename stringByAppendingPathComponent:filename];
        [self.download setDestination:destinationFilename allowOverwrite:NO];
    }
}

- (void)download:(NSURLDownload *)__unused aDownload didCreateDestination:(NSString *)path
{
    self.downloadFilename = path;
}

- (void)downloadDidFinish:(NSURLDownload *)__unused aDownload
{
    self.completionBlock([NSData dataWithContentsOfFile:self.downloadFilename], nil);
    self.completionBlock = nil;
    [self cleanup];
}

- (void)download:(NSURLDownload *)__unused aDownload didFailWithError:(NSError *)error
{
    [self cleanup];
    self.completionBlock(nil, error);
    self.completionBlock = nil;
}

@end
