//
//  SUDownloadDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUDownloadDriver.h"
#import "SUAppcastItem.h"
#import "SUFileManager.h"
#import "SULocalizations.h"
#import "SUHost.h"
#import "SUErrors.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUDownloadDriver () <NSURLDownloadDelegate>

@property (nonatomic, readonly) SUAppcastItem *updateItem;
@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, readonly, copy) NSString *cachePath;
@property (nonatomic) NSURLDownload *download;
@property (nonatomic, copy) NSString *temporaryDirectory;
@property (nonatomic, copy) NSString *downloadPath;
@property (nonatomic, weak) id<SUDownloadDriverDelegate> delegate;

@end

@implementation SUDownloadDriver

@synthesize updateItem = _updateItem;
@synthesize request = _request;
@synthesize host = _host;
@synthesize cachePath = _cachePath;
@synthesize download = _download;
@synthesize temporaryDirectory = _temporaryDirectory;
@synthesize downloadPath = _downloadPath;
@synthesize delegate = _delegate;

- (instancetype)initWithUpdateItem:(SUAppcastItem *)updateItem host:(SUHost *)host cachePath:(NSString *)cachePath userAgent:(NSString *)userAgent delegate:(id<SUDownloadDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _updateItem = updateItem;
        _host = host;
        _cachePath = [cachePath copy];
        _delegate = delegate;
        
        _request = [NSMutableURLRequest requestWithURL:updateItem.fileURL];
        [_request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    }
    return self;
}

- (void)downloadUpdate
{
    self.download = [[NSURLDownload alloc] initWithRequest:self.request delegate:self];
}

- (void)dealloc
{
    [self cleanup];
}

- (void)cancelTrashCleanup
{
    self.temporaryDirectory = nil;
}

- (void)cleanup
{
    NSString *temporaryDirectory = self.temporaryDirectory;
    if (temporaryDirectory != nil) // temporaryDirectory contains downloadPath, so we implicitly delete both here.
    {
        if ([[NSFileManager defaultManager] fileExistsAtPath:temporaryDirectory]) {
            BOOL success = [[NSFileManager defaultManager] removeItemAtPath:temporaryDirectory error:NULL]; // Clean up the copied relauncher
            if (!success) {
                NSURL *tempDirURL = [NSURL fileURLWithPath:temporaryDirectory];
                if (tempDirURL != nil) {
                    [[SUFileManager fileManagerAllowingAuthorization:NO] moveItemAtURLToTrash:tempDirURL error:NULL];
                }
            }
        }
    }
    
    if (self.download != nil) {
        [self.download cancel];
        self.download = nil;
    }
    self.downloadPath = nil;
}

- (void)download:(NSURLDownload *)__unused d decideDestinationWithSuggestedFilename:(NSString *)name
{
    NSString *downloadFileName = [NSString stringWithFormat:@"%@ %@", [self.host name], [self.updateItem versionString]];
    
    NSString *cachePath = self.cachePath;
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
        
        [self cleanup];
        [self.delegate downloadDriverDidFailToDownloadUpdateWithError:error];
    } else {
        NSString *downloadPath = [tempDir stringByAppendingPathComponent:name];
        self.downloadPath = downloadPath;
        [self.download setDestination:downloadPath allowOverwrite:YES];
    }
    
    self.temporaryDirectory = tempDir;
}

- (void)download:(NSURLDownload *)__unused download didReceiveResponse:(NSURLResponse *)response
{
    [self.delegate downloadDriverDidReceiveResponse:response];
}

- (void)download:(NSURLDownload *)__unused download didReceiveDataOfLength:(NSUInteger)length
{
    [self.delegate downloadDriverDidReceiveDataOfLength:length];
}

- (void)downloadDidFinish:(NSURLDownload *)__unused d
{
    assert(self.updateItem);
    
    // If this fails, then we must have already cleaned up / cancelled
    if (self.download != nil && self.downloadPath != nil) {
        self.download = nil;
        [self.delegate downloadDriverDidDownloadUpdate];
    }
}

- (void)download:(NSURLDownload *)__unused download didFailWithError:(NSError *)error
{
    NSURL *failingUrl = error.userInfo[NSURLErrorFailingURLErrorKey];
    if (!failingUrl) {
        failingUrl = [self.updateItem fileURL];
    }
    
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                                    NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while downloading the update. Please try again later.", nil),
                                                                                    NSUnderlyingErrorKey: error,
                                                                                    }];
    if (failingUrl) {
        userInfo[NSURLErrorFailingURLErrorKey] = failingUrl;
    }
    
    NSError *downloadError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:userInfo];
    [self.delegate downloadDriverDidFailToDownloadUpdateWithError:downloadError];
}

- (BOOL)download:(NSURLDownload *)__unused download shouldDecodeSourceDataOfMIMEType:(NSString *)encodingType
{
    // We don't want the download system to extract our gzips.
    // Note that we use a substring matching here instead of direct comparison because the docs say "application/gzip" but the system *uses* "application/x-gzip". This is a documentation bug.
    return ([encodingType rangeOfString:@"gzip"].location == NSNotFound);
}

@end
