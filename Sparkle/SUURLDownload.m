//
//  SUURLDownload.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/13/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUURLDownload.h"
#import "SUXPCServiceInfo.h"
#import "SUAppcastDownloader.h"
#import "SUAppcastDownloaderProtocol.h"
#import "SUURLRequest.h"
#import "SUErrors.h"

void SUDownloadURLWithRequest(NSURLRequest * request, void (^completionBlock)(NSData * _Nullable, NSError * _Nullable))
{
    id<SUAppcastDownloaderProtocol> downloader = nil;
    NSXPCConnection *connection = nil;
    __block BOOL retrievedDownloadResult = NO;
    
    if (!SUXPCServiceExists(@APPCAST_DOWNLOADER_PRODUCT_NAME)) {
        downloader = [[SUAppcastDownloader alloc] init];
    } else {
        connection = [[NSXPCConnection alloc] initWithServiceName:@APPCAST_DOWNLOADER_BUNDLE_ID];
        connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUAppcastDownloaderProtocol)];
        
        __weak NSXPCConnection *weakConnection = connection;
        connection.interruptionHandler = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!retrievedDownloadResult) {
                    [weakConnection invalidate];
                }
            });
        };
        
        connection.invalidationHandler = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!retrievedDownloadResult) {
                    completionBlock(nil, [NSError errorWithDomain:SUSparkleErrorDomain code:SUDownloadError userInfo:nil]);
                }
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
