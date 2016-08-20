//
//  SUDownloadDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUDownloadDriver.h"
#import "SPUDownloaderDelegate.h"
#import "SPUDownloader.h"
#import "SPUXPCServiceInfo.h"
#import "SUAppcastItem.h"
#import "SUFileManager.h"
#import "SULocalizations.h"
#import "SUHost.h"
#import "SULog.h"
#import "SUErrors.h"
#import "SPUURLRequest.h"
#import "SUDownloadedUpdate.h"
#import "SPUDownloadData.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUDownloadDriver () <SPUDownloaderDelegate>

@property (nonatomic) id<SPUDownloaderProtocol> downloader;
@property (nonatomic) NSXPCConnection *connection;
@property (nonatomic, readonly) SUAppcastItem *updateItem;
@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, copy) NSString *temporaryDirectory;
@property (nonatomic, copy) NSString *downloadName;
@property (nonatomic, weak) id<SUDownloadDriverDelegate> delegate;
@property (nonatomic) BOOL retrievedDownloadResult;
@property (nonatomic) BOOL retrievedDownloadResponse;
@property (nonatomic) NSUInteger expectedContentLength;
@property (nonatomic) BOOL cleaningUp;

@end

@implementation SUDownloadDriver

@synthesize downloader = _downloader;
@synthesize connection = _connection;
@synthesize updateItem = _updateItem;
@synthesize request = _request;
@synthesize host = _host;
@synthesize temporaryDirectory = _temporaryDirectory;
@synthesize downloadName = _downloadName;
@synthesize delegate = _delegate;
@synthesize retrievedDownloadResult = _retrievedDownloadResult;
@synthesize retrievedDownloadResponse = _retrievedDownloadResponse;
@synthesize expectedContentLength = _expectedContentLength;
@synthesize cleaningUp = _cleaningUp;

- (instancetype)initWithUpdateItem:(SUAppcastItem *)updateItem host:(SUHost *)host userAgent:(NSString *)userAgent delegate:(id<SUDownloadDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _updateItem = updateItem;
        _host = host;
        _delegate = delegate;
        
        _request = [NSMutableURLRequest requestWithURL:updateItem.fileURL];
        [_request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
        
        if (!SPUXPCServiceExists(@DOWNLOADER_BUNDLE_ID)) {
            _downloader = [[SPUDownloader alloc] initWithDelegate:self];
        } else {
            _connection = [[NSXPCConnection alloc] initWithServiceName:@DOWNLOADER_BUNDLE_ID];
            _connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SPUDownloaderProtocol)];
            _connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SPUDownloaderDelegate)];
            _connection.exportedObject = self;
            
            _downloader = _connection.remoteObjectProxy;
        }
    }
    return self;
}

- (void)downloadUpdate
{
    NSString *bundleIdentifier = self.host.bundle.bundleIdentifier;
    assert(bundleIdentifier != nil);
    
    __weak SUDownloadDriver *weakSelf = self;
    
    self.connection.interruptionHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            SUDownloadDriver *strongSelf = weakSelf;
            if (strongSelf != nil && !strongSelf.retrievedDownloadResult) {
                [strongSelf.connection invalidate];
            }
        });
    };
    
    self.connection.invalidationHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            SUDownloadDriver *strongSelf = weakSelf;
            if (strongSelf != nil && !strongSelf.retrievedDownloadResult && !strongSelf.cleaningUp) {
                SULog(@"Connection to update downloader was invalidated");
                
                NSDictionary *userInfo =
                @{
                  NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while downloading the update. Please try again later.", nil),
                  };
                
                NSError *downloadError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:userInfo];
                
                [strongSelf.delegate downloadDriverDidFailToDownloadUpdateWithError:downloadError];
            }
        });
    };
    
    [self.connection resume];
    
    [self.delegate downloadDriverWillBeginDownload];
    
    NSString *desiredFilename = [NSString stringWithFormat:@"%@ %@", [self.host name], [self.updateItem versionString]];
    [self.downloader startPersistentDownloadWithRequest:[SPUURLRequest URLRequestWithRequest:self.request] bundleIdentifier:bundleIdentifier desiredFilename:desiredFilename];
}

- (void)cleanup
{
    self.cleaningUp = YES;
    
    if (self.connection != nil) {
        [self.connection invalidate];
        self.connection = nil;
    }
    self.downloadName = nil;
    self.downloader = nil;
}

- (void)downloaderDidFinishWithTemporaryDownloadData:(SPUDownloadData * _Nullable)__unused downloadData
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.retrievedDownloadResult = YES;
        
        if (self.expectedContentLength > 0 && self.updateItem.contentLength > 0 && self.expectedContentLength != self.updateItem.contentLength) {
            SULog(@"Warning: Downloader's expected content length (%lu) != Appcast item's length (%lu)", self.expectedContentLength, self.updateItem.contentLength);
        }
        
        SUDownloadedUpdate *downloadedUpdate = [[SUDownloadedUpdate alloc] initWithAppcastItem:self.updateItem downloadName:self.downloadName temporaryDirectory:self.temporaryDirectory];
        
        [self.delegate downloadDriverDidDownloadUpdate:downloadedUpdate];
        [self cleanup];
    });
}

- (void)downloaderDidFailWithError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.retrievedDownloadResult = YES;
        
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
        
        [self cleanup];
    });
}

- (void)downloaderDidSetDestinationName:(NSString *)destinationName temporaryDirectory:(NSString *)temporaryDirectory
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.downloadName = destinationName;
        self.temporaryDirectory = temporaryDirectory;
    });
}

- (void)downloaderDidReceiveExpectedContentLength:(int64_t)expectedContentLength
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // We only notify the expected content length once and we try to use the content length from the appcast instead of from the downloader,
        // so that we have an expected length for the entire download rather than a single piece of block
        if (!self.retrievedDownloadResponse) {
            [self.delegate downloadDriverDidReceiveExpectedContentLength:(self.updateItem.contentLength > 0 ? self.updateItem.contentLength : (NSUInteger)expectedContentLength)];
            self.retrievedDownloadResponse = YES;
        }
        
        // Accumulate expected content length from downloader so we can later verify if the total length matches with the content length from the appcast
        if (expectedContentLength > 0 && expectedContentLength != NSURLResponseUnknownLength) {
            self.expectedContentLength += (NSUInteger)expectedContentLength;
        }
    });
}

- (void)downloaderDidReceiveDataOfLength:(NSUInteger)length
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate downloadDriverDidReceiveDataOfLength:length];
    });
}

@end
