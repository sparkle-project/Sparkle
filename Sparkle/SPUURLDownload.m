//
//  SUURLDownload.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/13/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUURLDownload.h"
#import "SPUXPCServiceInfo.h"
#import "SPUURLRequest.h"
#import "SPUDownloadData.h"
#import "SPUDownloaderProtocol.h"
#import "SPUDownloaderDelegate.h"
#import "SPUDownloader.h"
#import "SUErrors.h"


#include "AppKitPrevention.h"

@interface SPUTemporaryDownloaderDelegate : NSObject <SPUDownloaderDelegate>

@property (nonatomic, copy) void (^completionBlock)(SPUDownloadData * _Nullable, NSError * _Nullable);

@end

@implementation SPUTemporaryDownloaderDelegate

@synthesize completionBlock = _completionBlock;

- (instancetype)initWithCompletion:(void (^)(SPUDownloadData * _Nullable, NSError * _Nullable))completionBlock
{
    self = [super init];
    if (self != nil) {
        _completionBlock = [completionBlock copy];
    }
    return self;
}

- (void)downloaderDidSetDestinationName:(NSString *)__unused destinationName temporaryDirectory:(NSString *)__unused temporaryDirectory
{
}

- (void)downloaderDidReceiveExpectedContentLength:(int64_t)__unused expectedContentLength
{
}

- (void)downloaderDidReceiveDataOfLength:(uint64_t)__unused length
{
}

- (void)downloaderDidFinishWithTemporaryDownloadData:(SPUDownloadData * _Nullable)downloadData
{
    self.completionBlock(downloadData, nil);
    self.completionBlock = nil;
}

- (void)downloaderDidFailWithError:(NSError *)error
{
    self.completionBlock(nil, error);
    self.completionBlock = nil;
}

@end

void SPUDownloadURLWithRequest(NSURLRequest * request, void (^completionBlock)(SPUDownloadData * _Nullable, NSError * _Nullable))
{
    id<SPUDownloaderProtocol> downloader = nil;
    NSXPCConnection *connection = nil;
    __block BOOL retrievedDownloadResult = NO;
    
    SPUTemporaryDownloaderDelegate *temporaryDownloaderDelegate = [[SPUTemporaryDownloaderDelegate alloc] initWithCompletion:^(SPUDownloadData * _Nullable downloadData, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!retrievedDownloadResult) {
                retrievedDownloadResult = YES;
                [connection invalidate];
                
                if (downloadData == nil || downloadData.data == nil) {
                    completionBlock(nil, error);
                } else {
                    completionBlock(downloadData, nil);
                }
            }
        });
    }];
    
    if (!SPUXPCServiceExists(@DOWNLOADER_BUNDLE_ID)) {
        downloader = [[SPUDownloader alloc] initWithDelegate:temporaryDownloaderDelegate];
    } else {
        connection = [[NSXPCConnection alloc] initWithServiceName:@DOWNLOADER_BUNDLE_ID];
        connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SPUDownloaderProtocol)];
        connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SPUDownloaderDelegate)];
        connection.exportedObject = temporaryDownloaderDelegate;
        
        connection.interruptionHandler = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!retrievedDownloadResult) {
                    // We'll break the retain cycle in the invalidation handler
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
                    [connection invalidate];
#pragma clang diagnostic pop
                }
            });
        };
        
        connection.invalidationHandler = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!retrievedDownloadResult) {
                    completionBlock(nil, [NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:nil]);
                }
                
                // Break the retain cycle
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
                connection.interruptionHandler = nil;
                connection.invalidationHandler = nil;
#pragma clang diagnostic pop
            });
        };
        
        [connection resume];
        
        downloader = connection.remoteObjectProxy;
    }
    
    [downloader startTemporaryDownloadWithRequest:[SPUURLRequest URLRequestWithRequest:request]];
}
