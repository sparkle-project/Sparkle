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
#import "SUErrors.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUDownloadDriver () <SUDownloaderDelegate>

@property (nonatomic) NSXPCConnection *connection;
@property (nonatomic, readonly) SUAppcastItem *updateItem;
@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, copy) NSString *temporaryDirectory;
@property (nonatomic, copy) NSString *downloadPath;
@property (nonatomic, weak) id<SUDownloadDriverDelegate> delegate;

@end

@implementation SUDownloadDriver

@synthesize connection = _connection;
@synthesize updateItem = _updateItem;
@synthesize request = _request;
@synthesize host = _host;
@synthesize temporaryDirectory = _temporaryDirectory;
@synthesize downloadPath = _downloadPath;
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
        
        _connection = [[NSXPCConnection alloc] initWithServiceName:@"org.sparkle-project.UpdateDownloader"];
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
    
    [self.connection.remoteObjectProxy startDownloadWithRequest:self.request bundleIdentifier:bundleIdentifier desiredFilename:[NSString stringWithFormat:@"%@ %@", [self.host name], [self.updateItem versionString]]];
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
    if (self.connection != nil) {
        [self.connection invalidate];
        self.connection = nil;
    }
    self.downloadPath = nil;
}

- (void)downloaderDidSetDestination:(NSString *)destinationPath temporaryDirectory:(NSString *)temporaryDirectory
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.downloadPath = destinationPath;
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

- (void)downloaderDidFinish
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // If this fails, then we must have already cleaned up / cancelled
        if (self.connection != nil) {
            [self.connection invalidate];
            self.connection = nil;
            
            [self.delegate downloadDriverDidDownloadUpdate];
        }
    });
}

- (void)downloaderDidFailWithError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
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
    });
}

@end
