//
//  SUXPCURLDownload.h
//  Sparkle
//
//  Created by Erik Aderstedt on 2012-08-09.
//
//

#import <Foundation/Foundation.h>

@interface SUXPCURLDownload : NSObject
{
    id <NSURLDownloadDelegate> _delegate; // weak ref
    xpc_connection_t _connection;
    xpc_connection_t _delegateConnection;
    NSURLRequest *_request;
    NSThread *_startedThread; // weak ref
    
    BOOL _allowOverwrite;
    NSString *_destination;
    NSString *_connectionDestination;
    NSError *_downloadError;
}

- (id <NSURLDownloadDelegate>)delegate;
- (void)setDelegate:(id <NSURLDownloadDelegate>)delegate;

- (id)initWithRequest:(NSURLRequest *)request delegate:(id <NSURLDownloadDelegate>)delegate;
- (void)setDestination:(NSString *)path allowOverwrite:(BOOL)allowOverwrite;

@end
