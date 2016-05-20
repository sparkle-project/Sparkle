//
//  SUDownloadDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUDownloadDriver.h"
#import "SUDownloaderDelegate.h"
#import "SUUpdateDownloader.h"
#import "SUXPCServiceInfo.h"
#import "SUAppcastItem.h"
#import "SUFileManager.h"
#import "SULocalizations.h"
#import "SUHost.h"
#import "SULog.h"
#import "SUErrors.h"
#import "SUURLRequest.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUDownloadDriver () <SUDownloaderDelegate>

@property (nonatomic) id<SUUpdateDownloaderProtocol> downloader;
@property (nonatomic) NSXPCConnection *connection;
@property (nonatomic, readonly) SUAppcastItem *updateItem;
@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, copy) NSString *temporaryDirectory;
@property (nonatomic, copy) NSString *downloadName;
@property (nonatomic, weak) id<SUDownloadDriverDelegate> delegate;
@property (nonatomic) BOOL retrievedDownloadResult;

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

- (instancetype)initWithUpdateItem:(SUAppcastItem *)updateItem host:(SUHost *)host userAgent:(NSString *)userAgent delegate:(id<SUDownloadDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _updateItem = updateItem;
        _host = host;
        _delegate = delegate;
        
        _request = [NSMutableURLRequest requestWithURL:updateItem.fileURL];
        [_request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
        
        if (!SUXPCServiceExists(@UPDATE_DOWNLOADER_PRODUCT_NAME)) {
            _downloader = [[SUUpdateDownloader alloc] initWithDelegate:self];
        } else {
            _connection = [[NSXPCConnection alloc] initWithServiceName:@UPDATE_DOWNLOADER_BUNDLE_ID];
            _connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUUpdateDownloaderProtocol)];
            _connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUDownloaderDelegate)];
            _connection.exportedObject = self;
            
            _downloader = _connection.remoteObjectProxy;
        }
    }
    return self;
}

- (void)downloadUpdate
{
    [self.connection resume];
    
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
            if (strongSelf != nil && !strongSelf.retrievedDownloadResult) {
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
    
    [self.delegate downloadDriverWillBeginDownload];
    
    NSString *desiredFilename = [NSString stringWithFormat:@"%@ %@", [self.host name], [self.updateItem versionString]];
    [self.downloader startDownloadWithRequest:[SUURLRequest URLRequestWithRequest:self.request] bundleIdentifier:bundleIdentifier desiredFilename:desiredFilename];
}

- (void)dealloc
{
    [self cleanup];
}

- (void)cleanup
{
    // It's very crucial to wait until they are done with completion before invalidating our XPC connection (if there is one)
    // Otherwise we can run into some unfortunate crashes
    [self.downloader cleanupWithCompletion:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.connection != nil) {
                [self.connection invalidate];
                self.connection = nil;
            }
            self.downloadName = nil;
            self.downloader = nil;
        });
    }];
}

- (void)downloaderDidFinishDownloading
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.retrievedDownloadResult = YES;
        
        [self.delegate downloadDriverDidDownloadUpdate];
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

- (void)downloaderDidReceiveResponse:(NSURLResponse *)response
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate downloadDriverDidReceiveResponse:response];
    });
}

- (void)downloaderDidReceiveDataOfLength:(NSUInteger)length
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.delegate downloadDriverDidReceiveDataOfLength:length];
    });
}

@end
