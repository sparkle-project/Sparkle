//
//  SPUDownloadDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUDownloadDriver.h"
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
#import "SPUDownloadedUpdate.h"
#import "SPUDownloadData.h"


#include "AppKitPrevention.h"

@interface SPUDownloadDriver () <SPUDownloaderDelegate>

@property (nonatomic) id<SPUDownloaderProtocol> downloader;
@property (nonatomic) NSXPCConnection *connection;
@property (nonatomic, readonly) SUAppcastItem *updateItem;
@property (nonatomic, readonly, nullable) SUAppcastItem *secondaryUpdateItem;
@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, copy) NSString *temporaryDirectory;
@property (nonatomic, copy) NSString *downloadName;
@property (nonatomic, weak) id<SPUDownloadDriverDelegate> delegate;
@property (nonatomic) BOOL retrievedDownloadResult;
@property (nonatomic) uint64_t expectedContentLength;
@property (nonatomic) BOOL cleaningUp;

@end

@implementation SPUDownloadDriver

@synthesize downloader = _downloader;
@synthesize connection = _connection;
@synthesize updateItem = _updateItem;
@synthesize secondaryUpdateItem = _secondaryUpdateItem;
@synthesize request = _request;
@synthesize inBackground = _inBackground;
@synthesize host = _host;
@synthesize temporaryDirectory = _temporaryDirectory;
@synthesize downloadName = _downloadName;
@synthesize delegate = _delegate;
@synthesize retrievedDownloadResult = _retrievedDownloadResult;
@synthesize expectedContentLength = _expectedContentLength;
@synthesize cleaningUp = _cleaningUp;

- (instancetype)initWithHost:(SUHost *)host
{
    self = [super init];
    if (self != nil) {
        _host = host;
        
        if (!SPUXPCServiceIsEnabled(SUEnableDownloaderServiceKey)) {
            _downloader = [[SPUDownloader alloc] initWithDelegate:self];
        } else {
            _connection = [[NSXPCConnection alloc] initWithServiceName:@DOWNLOADER_BUNDLE_ID];
            _connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SPUDownloaderProtocol)];
            _connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SPUDownloaderDelegate)];
            _connection.exportedObject = self;
            
            _downloader = _connection.remoteObjectProxy;
            
            __weak SPUDownloadDriver *weakSelf = self;
            
            _connection.interruptionHandler = ^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    SPUDownloadDriver *strongSelf = weakSelf;
                    if (strongSelf != nil && !strongSelf.retrievedDownloadResult) {
                        [strongSelf.connection invalidate];
                    }
                });
            };
            
            _connection.invalidationHandler = ^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    SPUDownloadDriver *strongSelf = weakSelf;
                    if (strongSelf != nil && !strongSelf.retrievedDownloadResult && !strongSelf.cleaningUp) {
                        strongSelf.downloader = nil;
                        
                        SULog(SULogLevelError, @"Connection to update downloader was invalidated");
                        
                        NSDictionary *userInfo =
                        @{
                          NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while downloading the update. Please try again later.", nil),
                          };
                        
                        NSError *downloadError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:userInfo];
                        
                        [strongSelf.delegate downloadDriverDidFailToDownloadFileWithError:downloadError];
                    }
                });
            };
            
            [_connection resume];
        }
    }
    return self;
}

- (instancetype)initWithRequestURL:(NSURL *)requestURL host:(SUHost *)host userAgent:(NSString * _Nullable)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background delegate:(id<SPUDownloadDriverDelegate>)delegate
{
    self = [self initWithHost:host];
    if (self != nil) {
        _delegate = delegate;
        _inBackground = background;
        
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestURL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30.0];
        
        if (userAgent != nil) {
            [request setValue:(NSString * _Nonnull)userAgent forHTTPHeaderField:@"User-Agent"];
        }
        
        request.networkServiceType = background ? NSURLNetworkServiceTypeBackground : NSURLNetworkServiceTypeDefault;

        if (httpHeaders != nil) {
            for (NSString *key in httpHeaders) {
                NSString *value = [httpHeaders objectForKey:key];
                [request setValue:value forHTTPHeaderField:key];
            }
        }
        
        _request = request;
    }
    return self;
}

- (instancetype)initWithUpdateItem:(SUAppcastItem *)updateItem secondaryUpdateItem:(SUAppcastItem * _Nullable)secondaryUpdateItem host:(SUHost *)host userAgent:(NSString * _Nullable)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background delegate:(id<SPUDownloadDriverDelegate>)delegate
{
    NSURL *updateFileURL = updateItem.fileURL;
    assert(updateFileURL != nil);
    
    self = [self initWithRequestURL:updateFileURL host:host userAgent:userAgent httpHeaders:httpHeaders inBackground:background delegate:delegate];
    if (self != nil) {
        _updateItem = updateItem;
        _secondaryUpdateItem = secondaryUpdateItem;
    }
    return self;
}

- (void)downloadFile
{
    if ([self.delegate respondsToSelector:@selector(downloadDriverWillBeginDownload)]) {
        [self.delegate downloadDriverWillBeginDownload];
    }
    
    if (self.updateItem != nil) {
        NSString *desiredFilename = [NSString stringWithFormat:@"%@ %@", [self.host name], [self.updateItem versionString]];
        
        NSString *bundleIdentifier = self.host.bundle.bundleIdentifier;
        assert(bundleIdentifier != nil);
        
        [self.downloader startPersistentDownloadWithRequest:[SPUURLRequest URLRequestWithRequest:self.request] bundleIdentifier:bundleIdentifier desiredFilename:desiredFilename];
    } else {
        [self.downloader startTemporaryDownloadWithRequest:[SPUURLRequest URLRequestWithRequest:self.request]];
    }
}

- (void)removeDownloadedUpdate:(SPUDownloadedUpdate *)downloadedUpdate
{
    NSString *bundleIdentifier = self.host.bundle.bundleIdentifier;
    assert(bundleIdentifier != nil);
    
    if (bundleIdentifier != nil) {
        // Grab eg "0bCSun8tj" from org.sparkle-project.Sparkle/PersistentDownloads/0bCSun8tj/Sparkle Test App 2.0/
        NSString *tempDirectoryName = downloadedUpdate.temporaryDirectory.stringByDeletingLastPathComponent.lastPathComponent;
        
        [self.downloader removeDownloadDirectory:tempDirectoryName bundleIdentifier:bundleIdentifier];
    }
}

- (void)cleanup:(void (^)(void))completionHandler
{
    void (^cleanupBlock)(void) = ^{
        self.cleaningUp = YES;
        
        if (self.connection != nil) {
            [self.connection invalidate];
            self.connection = nil;
        }
        self.downloadName = nil;
        self.downloader = nil;
        
        completionHandler();
    };
    
    if (self.downloader == nil) {
        cleanupBlock();
    } else {
        [self.downloader cleanup:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                cleanupBlock();
            });
        }];
    }
}

- (void)downloaderDidFinishWithTemporaryDownloadData:(SPUDownloadData * _Nullable)downloadData
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.retrievedDownloadResult = YES;
        
        if (self.updateItem != nil) {
            if (self.expectedContentLength > 0 && self.updateItem.contentLength > 0 && self.expectedContentLength != self.updateItem.contentLength) {
                SULog(SULogLevelError, @"Warning: Downloader's expected content length (%llu) != Appcast item's length (%llu)", self.expectedContentLength, self.updateItem.contentLength);
            }
            
            SPUDownloadedUpdate *downloadedUpdate = [[SPUDownloadedUpdate alloc] initWithAppcastItem:self.updateItem secondaryAppcastItem:self.secondaryUpdateItem downloadName:self.downloadName temporaryDirectory:self.temporaryDirectory];
            
            if ([self.delegate respondsToSelector:@selector(downloadDriverDidDownloadUpdate:)]) {
                [self.delegate downloadDriverDidDownloadUpdate:downloadedUpdate];
            }
        } else {
            assert(downloadData != nil);
            SPUDownloadData *nonNullDownloadData = downloadData;
            if ([self.delegate respondsToSelector:@selector(downloadDriverDidDownloadData:)]) {
                [self.delegate downloadDriverDidDownloadData:nonNullDownloadData];
            }
        }
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
        [self.delegate downloadDriverDidFailToDownloadFileWithError:downloadError];
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
        // Fallback to appcast item's content length if we don't get the length from HTTP header
        if ([self.delegate respondsToSelector:@selector(downloadDriverDidReceiveExpectedContentLength:)]) {
            [self.delegate downloadDriverDidReceiveExpectedContentLength:expectedContentLength > 0 ? (uint64_t)expectedContentLength : self.updateItem.contentLength];
        }
        
        // Reset expected content length from downloader
        // Later we verify if the total length matches with the content length from the appcast
        if (expectedContentLength > 0) {
            self.expectedContentLength = (uint64_t)expectedContentLength;
        }
    });
}

- (void)downloaderDidReceiveDataOfLength:(uint64_t)length
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.delegate respondsToSelector:@selector(downloadDriverDidReceiveDataOfLength:)]) {
            [self.delegate downloadDriverDidReceiveDataOfLength:length];
        }
    });
}

@end
