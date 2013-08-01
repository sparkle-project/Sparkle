//
//  SUDSDownloader.h
//  Sparkle
//
//  Created by Dmytro Tretiakov on 8/1/13.
//
//

#import <Foundation/Foundation.h>

#define DEBUG_LOGGING_ENABLED defined(DEBUG) && 0

@class SUDSDownloader;

typedef void (^SUDSDownloadDidBegin)(SUDSDownloader *downloader);
typedef void (^SUDSDownloadDidFinish)(SUDSDownloader *downloader);
typedef void (^SUDSDownloadDidFail)(SUDSDownloader *downloader, NSError *error);
typedef void (^SUDSDownloadDidReceiveResponse)(SUDSDownloader *downloader, NSURLResponse *response);
typedef void (^SUDSDownloadDidReceiveData)(SUDSDownloader *downloader, NSUInteger dataLength);
typedef void (^SUDSDownloadDidCreateDestination)(SUDSDownloader *downloader, NSString *destinationPath);

typedef struct SUDSDownloaderCallBacks
{
    SUDSDownloadDidBegin    downloadDidBegin;
    SUDSDownloadDidFinish   downloadDidFinish;
    SUDSDownloadDidFail     downloadDidFail;
    
    SUDSDownloadDidReceiveResponse      downloadDidReceiveResponse;
    SUDSDownloadDidReceiveData          downloadDidReceiveData;
    SUDSDownloadDidCreateDestination    downloadDidCreateDestination;
} SUDSDownloaderCallBacks;

FOUNDATION_EXTERN SUDSDownloaderCallBacks SUDSCopyDownloaderCallBacks(SUDSDownloaderCallBacks callBacks);
FOUNDATION_EXTERN void SUDSReleaseDownloaderCallBacks(SUDSDownloaderCallBacks callBacks);

@interface SUDSDownloader : NSObject <NSURLDownloadDelegate>
{
@private
    NSURLRequest *_request;
    NSString *_destFilePath;
    SUDSDownloaderCallBacks _callBacks;
    
    NSURLDownload *_download;
}

- (id)initWithURLRequest:(NSURLRequest *)request destinationPath:(NSString *)filePath;
+ (id)downloaderWithURLRequest:(NSURLRequest *)request destinationPath:(NSString *)filePath;

- (NSURLRequest *)request;
- (NSString *)destinationPath;
- (void)setCallBacks:(SUDSDownloaderCallBacks)callBacks;

- (void)startDownload;
- (void)stopDownload;
- (BOOL)isInProgress;

@end
