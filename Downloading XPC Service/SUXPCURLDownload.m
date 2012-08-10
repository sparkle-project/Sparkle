//
//  SUXPCURLDownload.m
//  Sparkle
//
//  Created by Erik Aderstedt on 2012-08-09.
//
//

#import "SUXPCURLDownload.h"

@implementation SUXPCURLDownload

- (id)initWithRequest:(NSURLRequest *)_request delegate:(id <NSURLDownloadDelegate>)_delegate {
    if ((self = [super init])) {
        progress = 0.0;
        total = -1.0;

        request = [_request retain];
        delegate = [_delegate retain];
        
        // Set up a connection.
        connection = [self getSandboxXPCService];
        dispatch_async(dispatch_get_current_queue(), ^{
            [self startDownload:[_request URL]];
        });
        
    }
    return self;
}

- (void)dealloc {
    [request release];
    [delegate release];
    
    [super dealloc];
}

- (NSURLRequest *)request {
    return request;
}

- (void)startDownload:(NSURL *)url {

    // Send a message to download a specific url.
    if ([delegate respondsToSelector:@selector(download:decideDestinationWithSuggestedFilename:)] && destination == nil) {
        [delegate download:(NSURLDownload *)self decideDestinationWithSuggestedFilename:[url lastPathComponent]];
    } else {
        destination = [url lastPathComponent];
    }
    
    // ivar 'destination' now contains the destination URL.
    
    NSURL *tempFolder = [[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
    NSString *tempFileTemplate = [[tempFolder URLByAppendingPathComponent:@"fetch.XXXXXXXX"] path];

    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_string(message, "sourceURL", [[url absoluteString] cStringUsingEncoding:NSUTF8StringEncoding]);
    xpc_dictionary_set_string(message, "tempFileTemplate", [tempFileTemplate cStringUsingEncoding:NSUTF8StringEncoding]);
    xpc_dictionary_set_string(message, "fileNameSuggestion", [[destination lastPathComponent] cStringUsingEncoding:NSUTF8StringEncoding]);
    xpc_dictionary_set_connection(message, "connection", delegateConnection);
    xpc_connection_send_message_with_reply(connection, message, dispatch_get_main_queue(), ^(xpc_object_t object) {
        xpc_type_t type = xpc_get_type(object);
        
        if (type == XPC_TYPE_ERROR || (type == XPC_TYPE_DICTIONARY && xpc_dictionary_get_int64(object, "errCode"))) {
            if ([delegate respondsToSelector:@selector(download:didFailWithError:)]) {
                [delegate download:(NSURLDownload *)self didFailWithError:[NSError errorWithDomain:NSOSStatusErrorDomain code:(NSInteger)xpc_dictionary_get_int64(object, "errCode") userInfo:nil]];
            }
        } else {
            int fd = xpc_dictionary_dup_fd(object, "fd");
            close(fd);
            if ([delegate respondsToSelector:@selector(downloadDidFinish:)]) {
                [delegate downloadDidFinish:(NSURLDownload *)self];
            }
        }
    });
    xpc_release(message);

}

- (id <NSURLDownloadDelegate>) delegate {
    return delegate;
}

- (void)setDelegate:(id <NSURLDownloadDelegate>)_delegate {
    id <NSURLDownloadDelegate> oldDelegate = delegate;
    delegate = [_delegate retain];
    [oldDelegate release];
}

- (void)setDestination:(NSString *)path allowOverwrite:(BOOL)_allowOverwrite {
    destination = [path retain];
    allowOverwrite = _allowOverwrite;
}

- (void)cancel {
    xpc_connection_cancel(connection);
}

- (xpc_connection_t)getSandboxXPCService {
    // Set up two connections, one for instructing the XPC and getting a response,
    // and another to listen for incoming connections for progress and file creation
    // notifications.
    
    connection = xpc_connection_create("com.andymatuschak.Sparkle.download-service", dispatch_get_main_queue());
    if (!connection) {
        NSLog(@"Can't connect to XPC service");
        return (NULL);
    }
    xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
        xpc_type_t type = xpc_get_type(event);
        
        if (type == XPC_TYPE_ERROR) {
            
            if (event == XPC_ERROR_CONNECTION_INTERRUPTED) {
                // The service has either cancaled itself, crashed, or been
                // terminated.  The XPC connection is still valid and sending a
                // message to it will re-launch the service.  If the service is
                // state-full, this is the time to initialize the new service.
                
            } else if (event == XPC_ERROR_CONNECTION_INVALID) {
                // The service is invalid. Either the service name supplied to
                // xpc_connection_create() is incorrect or we (this process) have
                // canceled the service; we can do any cleanup of appliation
                // state at this point.
                xpc_connection_cancel(delegateConnection);
                xpc_release(delegateConnection);
            }
        }
    });

    dispatch_queue_t delegate_queue = dispatch_queue_create("com.andymatuschak.Sparkle.download-service-delegate", NULL);
    assert(delegate_queue != NULL);

    delegateConnection = xpc_connection_create(NULL, delegate_queue);
    xpc_connection_set_event_handler(delegateConnection, ^(xpc_object_t event) {
        xpc_type_t type = xpc_get_type(event);
        
        if (type == XPC_TYPE_ERROR) {
            if (event == XPC_ERROR_TERMINATION_IMMINENT) {
                NSLog(@"received XPC_ERROR_TERMINATION_IMMINENT");
            } else if (event == XPC_ERROR_CONNECTION_INVALID) {
                NSLog(@"progress connection is closed");
            }
        } else if (type == XPC_TYPE_CONNECTION) {
            xpc_connection_t peer = (xpc_connection_t)event;
            // A new anonymous connection, from an XPC service that wants to supply us with updates.
            char *queue_name = NULL;
            dispatch_queue_t peer_event_queue = dispatch_queue_create(queue_name, NULL);
            assert(peer_event_queue != NULL);
            free(queue_name);
            
            xpc_connection_set_target_queue(peer, peer_event_queue);
            xpc_connection_set_event_handler(peer, ^(xpc_object_t nevent) {
                xpc_type_t ntype = xpc_get_type(nevent);
                if (ntype == XPC_TYPE_DICTIONARY) {
                    // Handle a message from the service. This can either be that the download failed, or a progress update.
                    __block bool progressValue = false;
                    __block bool didCreate = false;
                    
                    xpc_dictionary_apply(nevent, ^bool(const char *key, xpc_object_t v) {
                        if (!strcmp(key, "progressValue")) progressValue = true;
                        if (!strcmp(key, "didCreateDestination")) didCreate = true;
                        return true;
                    });
                    if (progressValue) {
                        if (total < 0) {
                            total = xpc_dictionary_get_double(nevent, "total");
                            if ([delegate respondsToSelector:@selector(download:didReceiveResponse:)]) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    
                                    // Ok, so this is another hack. We respond to the methods on NSURLResponse that we know the various updaters require.
                                    [delegate download:(NSURLDownload *)self didReceiveResponse:(NSURLResponse *)self];
                                });
                            }
                        }
                        double sofar = xpc_dictionary_get_double(nevent, "current");
                        if ([delegate respondsToSelector:@selector(download:didReceiveDataOfLength:)]) {
                            int netLength = (int)(sofar - progress);
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [delegate download:(NSURLDownload *)self didReceiveDataOfLength:netLength];
                            });
                            progress = sofar;
                        }
                    }
                    
                    if (didCreate && [delegate respondsToSelector:@selector(download:didCreateDestination:)]) {
                        NSString *destPath = [NSString stringWithCString:xpc_dictionary_get_string(nevent, "destPath") encoding:NSUTF8StringEncoding];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [delegate download:(NSURLDownload *)self didCreateDestination:destPath];
                        });
                    }
                }
            });
            xpc_connection_resume(peer);
        } 
    });
    
    // Need to resume the service in order for it to process messages.
    xpc_connection_resume(delegateConnection);
    xpc_connection_resume(connection);
    return (connection);
}

- (long long)expectedContentLength {
    return (long long)total;
}

@end
