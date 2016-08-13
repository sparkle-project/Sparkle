//
//  SUURLDownload.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/13/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUURLDownload.h"
#import "SPUXPCServiceInfo.h"
#import "SUTemporaryDownloader.h"
#import "SUTemporaryDownloaderProtocol.h"
#import "SPUURLRequest.h"
#import "SPUDownloadData.h"
#import "SUErrors.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

void SPUDownloadURLWithRequest(NSURLRequest * request, void (^completionBlock)(SPUDownloadData * _Nullable, NSError * _Nullable))
{
    id<SUTemporaryDownloaderProtocol> downloader = nil;
    NSXPCConnection *connection = nil;
    __block BOOL retrievedDownloadResult = NO;
    
    if (!SPUXPCServiceExists(@TEMPORARY_DOWNLOADER_BUNDLE_ID)) {
        downloader = [[SUTemporaryDownloader alloc] init];
    } else {
        connection = [[NSXPCConnection alloc] initWithServiceName:@TEMPORARY_DOWNLOADER_BUNDLE_ID];
        connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUTemporaryDownloaderProtocol)];
        
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
    
    [downloader startDownloadWithRequest:[SPUURLRequest URLRequestWithRequest:request] completion:^(SPUDownloadData * _Nullable downloadData, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            retrievedDownloadResult = YES;
            [connection invalidate];
            
            if (downloadData == nil || downloadData.data == nil) {
                completionBlock(nil, error);
            } else {
                completionBlock(downloadData, nil);
            }
        });
    }];
}
