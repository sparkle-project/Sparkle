//
//  SUDSDownloader.m
//  Sparkle
//
//  Created by Dmytro Tretiakov on 8/1/13.
//
//

#import "SUDSDownloader.h"

SUDSDownloaderCallBacks SUDSCopyDownloaderCallBacks(SUDSDownloaderCallBacks callBacks)
{
    SUDSDownloaderCallBacks callBacksCopy = {0};
    
    if (callBacks.downloadDidBegin)
        callBacksCopy.downloadDidBegin = Block_copy(callBacks.downloadDidBegin);
    if (callBacks.downloadDidFinish)
        callBacksCopy.downloadDidFinish = Block_copy(callBacks.downloadDidFinish);
    if (callBacks.downloadDidFail)
        callBacksCopy.downloadDidFail = Block_copy(callBacks.downloadDidFail);
    if (callBacks.downloadDidReceiveData)
        callBacksCopy.downloadDidReceiveData = Block_copy(callBacks.downloadDidReceiveData);
    if (callBacks.downloadDidCreateDestination)
        callBacksCopy.downloadDidCreateDestination = Block_copy(callBacks.downloadDidCreateDestination);
    if (callBacks.downloadDidReceiveResponse)
        callBacksCopy.downloadDidReceiveResponse = Block_copy(callBacks.downloadDidReceiveResponse);
    if (callBacks.downloadShouldDecodeSourceData)
        callBacksCopy.downloadShouldDecodeSourceData = Block_copy(callBacks.downloadShouldDecodeSourceData);
    
    return callBacksCopy;
}

void SUDSReleaseDownloaderCallBacks(SUDSDownloaderCallBacks callBacks)
{
    if (callBacks.downloadDidBegin)
        Block_release(callBacks.downloadDidBegin);
    if (callBacks.downloadDidFinish)
        Block_release(callBacks.downloadDidFinish);
    if (callBacks.downloadDidFail)
        Block_release(callBacks.downloadDidFail);
    if (callBacks.downloadDidReceiveData)
        Block_release(callBacks.downloadDidReceiveData);
    if (callBacks.downloadDidCreateDestination)
        Block_release(callBacks.downloadDidCreateDestination);
    if (callBacks.downloadDidReceiveResponse)
        Block_release(callBacks.downloadDidReceiveResponse);
    if (callBacks.downloadShouldDecodeSourceData)
        Block_release(callBacks.downloadShouldDecodeSourceData);
}

@implementation SUDSDownloader

- (id)initWithURLRequest:(NSURLRequest *)request destinationPath:(NSString *)filePath
{
    self = [super init];
    if (self != nil)
    {
        _request = [request retain];
        _destFilePath = [filePath copy];
    }
    
    return self;
}

+ (id)downloaderWithURLRequest:(NSURLRequest *)request destinationPath:(NSString *)filePath
{
    return [[[[self class] alloc] initWithURLRequest:request destinationPath:filePath] autorelease];
}

- (void)dealloc
{
    [self stopDownload];
    
    [_request release];
    [_destFilePath release];
    SUDSReleaseDownloaderCallBacks(_callBacks);
    
    [super dealloc];
}

- (NSURLRequest *)request
{
    return _request;
}

- (NSString *)destinationPath
{
    return _destFilePath;
}

- (void)setCallBacks:(SUDSDownloaderCallBacks)callBacks
{
    SUDSDownloaderCallBacks oldCallBacks = _callBacks;
    _callBacks = SUDSCopyDownloaderCallBacks(callBacks);
    SUDSReleaseDownloaderCallBacks(oldCallBacks);
}

- (void)startDownload
{
    [self stopDownload];
    
    // to ensure that parent folder exists
    [[NSFileManager defaultManager] createDirectoryAtPath:[_destFilePath stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    NSURLDownload *urlDownload = [[NSURLDownload alloc] initWithRequest:_request delegate:self];
    @synchronized (self)
    {
        _download = urlDownload;
    }
    
    [urlDownload setDestination:_destFilePath allowOverwrite:YES];
}

- (void)stopDownload
{
    @synchronized (self)
    {
        [_download cancel];
        [_download release];
        _download = nil;
    }
}

- (BOOL)isInProgress
{
    BOOL result = YES;
    @synchronized (self)
    {
        result = _download != nil;
    }
    
    return result;
}

#pragma mark -

- (void)downloadDidBegin:(NSURLDownload *)download
{
#if DEBUG_LOGGING_ENABLED
    NSLog(@"XPC Downloader did begin process.");
#endif
    if (_callBacks.downloadDidBegin)
        _callBacks.downloadDidBegin(self);
}

- (void)download:(NSURLDownload *)download didReceiveResponse:(NSURLResponse *)response
{
#if DEBUG_LOGGING_ENABLED
    NSLog(@"XPC Downloader did receive response: %@", [response description]);
#endif
    if (_callBacks.downloadDidReceiveResponse)
        _callBacks.downloadDidReceiveResponse(self, response);
}

- (void)download:(NSURLDownload *)download didCreateDestination:(NSString *)path
{
#if DEBUG_LOGGING_ENABLED
    NSLog(@"XPC Downloader did create destination: %@", path);
#endif
    if (_callBacks.downloadDidCreateDestination)
        _callBacks.downloadDidCreateDestination(self, path);
}

- (void)download:(NSURLDownload *)download didReceiveDataOfLength:(NSUInteger)length
{
#if DEBUG_LOGGING_ENABLED
    NSLog(@"XPC Downloader did receive data of length %ld bytes", (unsigned long)length);
#endif
    if (_callBacks.downloadDidReceiveData)
        _callBacks.downloadDidReceiveData(self, length);
}

- (void)download:(NSURLDownload *)download didFailWithError:(NSError *)error
{
#if DEBUG_LOGGING_ENABLED
    NSLog(@"XPC Downloader did fail: %@", [error description]);
#endif
    if (_callBacks.downloadDidFail)
        _callBacks.downloadDidFail(self, error);
    
    [self stopDownload];
}

- (void)downloadDidFinish:(NSURLDownload *)download
{
#if DEBUG_LOGGING_ENABLED
    NSLog(@"XPC Downloader did finish");
#endif
    if (_callBacks.downloadDidFinish)
        _callBacks.downloadDidFinish(self);
    
    [self stopDownload];
}

- (BOOL)download:(NSURLDownload *)download shouldDecodeSourceDataOfMIMEType:(NSString *)encodingType
{
    BOOL shouldDecode = NO;
    
#if DEBUG_LOGGING_ENABLED
    NSLog(@"XPC Downloader wants decode source data of MIME type: %@", encodingType);
#endif
    if (_callBacks.downloadShouldDecodeSourceData)
        shouldDecode = _callBacks.downloadShouldDecodeSourceData(self, encodingType);
    
    return shouldDecode;
}

@end
