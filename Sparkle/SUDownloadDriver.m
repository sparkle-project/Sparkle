//
//  SUDownloadDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUDownloadDriver.h"
#import "SUDownloaderDelegate.h"
#import "SUUpdateDownloaderProtocol.h"
#import "SUAppcastItem.h"
#import "SUFileManager.h"
#import "SULocalizations.h"
#import "SUHost.h"
#import "SULog.h"
#import "SUErrors.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUDownloadDriver () <SUDownloaderDelegate>

@property (nonatomic) NSXPCConnection *connection;
@property (nonatomic, readonly) SUAppcastItem *updateItem;
@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, copy) NSString *temporaryDirectory;
@property (nonatomic, copy) NSString *downloadName;
@property (nonatomic, weak) id<SUDownloadDriverDelegate> delegate;

@end

@implementation SUDownloadDriver

@synthesize connection = _connection;
@synthesize updateItem = _updateItem;
@synthesize request = _request;
@synthesize host = _host;
@synthesize temporaryDirectory = _temporaryDirectory;
@synthesize downloadName = _downloadName;
@synthesize delegate = _delegate;

- (instancetype)initWithUpdateItem:(SUAppcastItem *)updateItem host:(SUHost *)host userAgent:(NSString *)userAgent delegate:(id<SUDownloadDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _updateItem = updateItem;
        _host = host;
        _delegate = delegate;
        
        _request = [NSMutableURLRequest requestWithURL:updateItem.fileURL];
        [_request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
        
        _connection = [[NSXPCConnection alloc] initWithServiceName:@UPDATE_DOWNLOADER_BUNDLE_ID];
        _connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUUpdateDownloaderProtocol)];
        _connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUDownloaderDelegate)];
        _connection.exportedObject = self;
    }
    return self;
}

- (void)downloadUpdate
{
    [self.connection resume];
    
    NSString *bundleIdentifier = self.host.bundle.bundleIdentifier;
    assert(bundleIdentifier != nil);
    
    __weak SUDownloadDriver *weakSelf = self;
    __block BOOL retrievedDownloadResult = NO;
    
    self.connection.interruptionHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!retrievedDownloadResult) {
                [weakSelf.connection invalidate];
            }
        });
    };
    
    self.connection.invalidationHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            SUDownloadDriver *strongSelf = weakSelf;
            if (!retrievedDownloadResult && strongSelf != nil) {
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
    [self.connection.remoteObjectProxy startDownloadWithRequest:self.request bundleIdentifier:bundleIdentifier desiredFilename:desiredFilename completion:^(BOOL success, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            retrievedDownloadResult = YES;
            SUDownloadDriver *strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            
            if (!success) {
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
                [strongSelf.delegate downloadDriverDidFailToDownloadUpdateWithError:downloadError];
            } else {
                [strongSelf.delegate downloadDriverDidDownloadUpdate];
            }
        });
    }];
}

- (void)dealloc
{
    [self cleanup];
}

- (void)cleanup
{
    if (self.connection != nil) {
        [self.connection invalidate];
        self.connection = nil;
    }
    self.downloadName = nil;
}

- (void)downloaderDidSetDestinationName:(NSString *)destinationName temporaryDirectory:(NSString *)temporaryDirectory
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.downloadName = destinationName;
        self.temporaryDirectory = temporaryDirectory;
    });
}

- (void)downloaderDidFailToCreateTemporaryDirectoryWithError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self cleanup];
        [self.delegate downloadDriverDidFailToDownloadUpdateWithError:error];
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
