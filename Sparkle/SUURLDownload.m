//
//  SUURLDownload.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/13/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUURLDownload.h"
#import "SUXPCServiceInfo.h"
#import "SUTemporaryDownloader.h"
#import "SUTemporaryDownloaderProtocol.h"
#import "SUURLRequest.h"
#import "SUErrors.h"

void SUDownloadURLWithRequest(NSURLRequest * request, void (^completionBlock)(NSData * _Nullable, NSError * _Nullable))
{
    id<SUTemporaryDownloaderProtocol> downloader = nil;
    NSXPCConnection *connection = nil;
    __block BOOL retrievedDownloadResult = NO;
    
    if (!SUXPCServiceExists(@TEMPORARY_DOWNLOADER_PRODUCT_NAME)) {
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
    
    [downloader startDownloadWithRequest:[SUURLRequest URLRequestWithRequest:request] completion:^(NSData * _Nullable data, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            retrievedDownloadResult = YES;
            [connection invalidate];
            
            if (data == nil) {
                completionBlock(nil, error);
            } else {
                completionBlock(data, nil);
            }
        });
    }];
}
