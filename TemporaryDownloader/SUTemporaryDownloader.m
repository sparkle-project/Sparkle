//
//  SUTemporaryDownloader.m
//  TemporaryDownloader
//
//  Created by Mayur Pawashe on 4/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUTemporaryDownloader.h"
#import "SPUDownloadData.h"
#import "SPUURLRequest.h"
#import "SUErrors.h"
#import "SUConstants.h"

@interface SUTemporaryDownloader () <NSURLDownloadDelegate>

@property (nonatomic, copy) void (^completionBlock)(SPUDownloadData * _Nullable downloadData, NSError * _Nullable error);
@property (nonatomic) NSURLDownload *download;
@property (nonatomic, copy) NSString *downloadFilename;
@property (nonatomic) NSURLResponse *response;

@end

@implementation SUTemporaryDownloader

@synthesize completionBlock = _completionBlock;
@synthesize download = _download;
@synthesize downloadFilename = _downloadFilename;
@synthesize response = _response;

- (void)startDownloadWithRequest:(SPUURLRequest *)request completion:(void (^)(SPUDownloadData * _Nullable downloadData, NSError * _Nullable error))completionBlock
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

- (void)download:(NSURLDownload *)__unused download didReceiveResponse:(NSURLResponse *)response
{
    self.response = response;
}

- (void)downloadDidFinish:(NSURLDownload *)__unused aDownload
{
    assert(self.response != nil);
    assert(self.downloadFilename != nil);
    
    NSData *data = [NSData dataWithContentsOfFile:self.downloadFilename];
    if (data != nil) {
        // See SUPersistentDownloader as to why sending the NSURLResponse object over is not a good idea
        SPUDownloadData *downloadData = [[SPUDownloadData alloc] initWithData:data textEncodingName:self.response.textEncodingName MIMEType:self.response.MIMEType];
        self.completionBlock(downloadData, nil);
    } else {
        self.completionBlock(nil, [NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to read temporary downloaded data from %@", self.downloadFilename] }]);
    }
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
