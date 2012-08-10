//
//  SUXPCURLDownload.h
//  Sparkle
//
//  Created by Erik Aderstedt on 2012-08-09.
//
//

#import <Foundation/Foundation.h>

@interface SUXPCURLDownload : NSObject {
    id <NSURLDownloadDelegate> delegate;
    double progress;
    double total;
    xpc_connection_t connection;
    xpc_connection_t delegateConnection;
    NSURLRequest *request;
    
    BOOL allowOverwrite;
    NSString *destination;
}

- (id <NSURLDownloadDelegate>) delegate;
- (void)setDelegate:(id <NSURLDownloadDelegate>)_delegate;

- (id)initWithRequest:(NSURLRequest *)request delegate:(id <NSURLDownloadDelegate>)delegate;
- (void)setDestination:(NSString *)path allowOverwrite:(BOOL)allowOverwrite;

@end
