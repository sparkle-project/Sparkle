//
//  SUXPCURLDownload.m
//  Sparkle
//
//  Created by Erik Aderstedt on 2012-08-09.
//
//

#import "SUXPCURLDownload.h"
#import "SUDownloadServiceConstants.h"

static NSString * const kSUFetchFolderName = @"fetch.XXXXXXXX";

@interface SUXPCURLDownload (Private)

- (void)performBlock:(void (^)(void))block onThread:(NSThread *)thread synchronous:(BOOL)flag;
- (void)fireBlock:(void (^)(void))block;

@end

@implementation SUXPCURLDownload

- (id)initWithRequest:(NSURLRequest *)request delegate:(id <NSURLDownloadDelegate>)delegate
{
    self = [super init];
    if (self != nil)
    {
        _request = [request retain];
        _delegate = [delegate retain];
        _startedThread = [NSThread currentThread];
        
        // Set up a connection.
        _connection = [self getSandboxXPCService];
        dispatch_async(dispatch_get_current_queue(), ^{
            [self startDownload:request];
        });
    }
    
    return self;
}

- (void)dealloc
{
    [self cancel];
    
    [_request release];
    [_destination release];
    [_connectionDestination release];
    [_downloadError release];
    
    [super dealloc];
}

- (NSURLRequest *)request
{
    return _request;
}

- (void)startDownload:(NSURLRequest *)urlRequest
{
    // Send a message to download a specific url.
    if ([_delegate respondsToSelector:@selector(download:decideDestinationWithSuggestedFilename:)] && _destination == nil)
    {
        void (^block)(void) = ^{
            [_delegate download:(NSURLDownload *)self decideDestinationWithSuggestedFilename:[[urlRequest URL] lastPathComponent]];
        };
        [self performBlock:block onThread:_startedThread synchronous:YES];
    }
    else
    {
        _destination = [[[urlRequest URL] lastPathComponent] copy];
    }
    
    // ivar 'destination' now contains the destination URL.
    
    NSURL *tempFolder = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    NSString *tempFileTemplate = [[tempFolder URLByAppendingPathComponent:kSUFetchFolderName] path];
    NSString *tempFilePath = [tempFileTemplate stringByAppendingPathComponent:[_destination lastPathComponent]];
    _connectionDestination = [tempFilePath copy];
    
    NSData *requestData = [NSKeyedArchiver archivedDataWithRootObject:urlRequest];

    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_data(message, SUDownloadServiceURLRequestDataKey, [requestData bytes], [requestData length]);
    xpc_dictionary_set_string(message, SUDownloadServiceFilePathKey, [tempFilePath cStringUsingEncoding:NSUTF8StringEncoding]);
    xpc_dictionary_set_connection(message, SUDownloadServiceDelegateConnectionKey, _delegateConnection);
    xpc_connection_send_message_with_reply(_connection, message, dispatch_get_main_queue(), ^(xpc_object_t object) {
        xpc_type_t type = xpc_get_type(object);
        
        if (type == XPC_TYPE_ERROR ||
            (type == XPC_TYPE_DICTIONARY && noErr != xpc_dictionary_get_int64(object, SUDownloadServiceErrorCodeKey)))
        {
            if ([_delegate respondsToSelector:@selector(download:didFailWithError:)])
            {
#if DEBUG
                const char *errMessage = xpc_dictionary_get_string(object, SUDownloadServiceErrorMessageKey);
                if (errMessage != NULL)
                {
                    NSLog(@"Error message: %s", errMessage);
                }
                else if (_downloadError != nil)
                {
                    NSLog(@"Error message: %@", [_downloadError description]);
                }
#endif
                NSError *error = _downloadError;
                if (nil == error)
                {
                    NSInteger errCode = (NSInteger)xpc_dictionary_get_int64(object, SUDownloadServiceErrorCodeKey);
                    error = [NSError errorWithDomain:NSOSStatusErrorDomain code:errCode userInfo:nil];
                }
                
                void (^block)(void) = ^{
                    [_delegate download:(NSURLDownload *)self didFailWithError:error];
                };
                [self performBlock:block onThread:_startedThread synchronous:NO];
            }
        }
    });
    xpc_release(message);
}

- (id <NSURLDownloadDelegate>)delegate
{
    return _delegate;
}

- (void)setDelegate:(id <NSURLDownloadDelegate>)delegate
{
    _delegate = delegate;
}

- (void)setDestination:(NSString *)path allowOverwrite:(BOOL)allowOverwrite
{
    _destination = [path copy];
    _allowOverwrite = allowOverwrite;
}

- (void)cancel
{
    if (_connection)
    {
        xpc_connection_cancel(_connection);
        xpc_release(_connection);
        _connection = NULL;
    }
    if (_delegateConnection)
    {
        xpc_connection_cancel(_delegateConnection);
        xpc_release(_delegateConnection);
        _delegateConnection = NULL;
    }
}

- (xpc_connection_t)getSandboxXPCService
{
    // Set up two connections, one for instructing the XPC and getting a response,
    // and another to listen for incoming connections for progress and file creation
    // notifications.
    
    _connection = xpc_connection_create("com.andymatuschak.Sparkle.download-service", dispatch_get_main_queue());
    if (!_connection)
    {
        NSLog(@"Can't connect to XPC service");
        return (NULL);
    }
    
    xpc_connection_set_event_handler(_connection, ^(xpc_object_t event) {
        xpc_type_t type = xpc_get_type(event);
        
        if (type == XPC_TYPE_ERROR)
        {
            if (event == XPC_ERROR_CONNECTION_INTERRUPTED)
            {
                NSLog(@"Got XPC_ERROR_CONNECTION_INTERRUPTED error.");
                // The service has either cancaled itself, crashed, or been
                // terminated.  The XPC connection is still valid and sending a
                // message to it will re-launch the service.  If the service is
                // state-full, this is the time to initialize the new service.
                
            }
            else if (event == XPC_ERROR_CONNECTION_INVALID)
            {
                NSLog(@"Got XPC_ERROR_CONNECTION_INVALID error.");
                // The service is invalid. Either the service name supplied to
                // xpc_connection_create() is incorrect or we (this process) have
                // canceled the service; we can do any cleanup of appliation
                // state at this point.
                if (_delegateConnection)
                {
                    xpc_connection_cancel(_delegateConnection);
                    xpc_release(_delegateConnection);
                    _delegateConnection = NULL;
                }
            }
        }
    });

    dispatch_queue_t delegate_queue = dispatch_queue_create("com.andymatuschak.Sparkle.download-service-delegate", NULL);
    assert(delegate_queue != NULL);

    _delegateConnection = xpc_connection_create(NULL, delegate_queue);
    xpc_connection_set_context(_delegateConnection, delegate_queue);
    xpc_connection_set_finalizer_f(_delegateConnection, (xpc_finalizer_t)&dispatch_release);
    xpc_connection_set_event_handler(_delegateConnection, ^(xpc_object_t event) {
        xpc_type_t type = xpc_get_type(event);
        
        if (type == XPC_TYPE_ERROR)
        {
            if (event == XPC_ERROR_TERMINATION_IMMINENT)
            {
                NSLog(@"received XPC_ERROR_TERMINATION_IMMINENT");
            }
            else if (event == XPC_ERROR_CONNECTION_INVALID)
            {
                NSLog(@"progress connection is closed");
                dispatch_release(delegate_queue);
            }
        }
        else if (type == XPC_TYPE_CONNECTION)
        {
            xpc_connection_t peer = (xpc_connection_t)event;
            // A new anonymous connection, from an XPC service that wants to supply us with updates.
            char *queue_name = NULL;
            dispatch_queue_t peer_event_queue = dispatch_queue_create(queue_name, NULL);
            assert(peer_event_queue != NULL);
            free(queue_name);
            
            xpc_connection_set_target_queue(peer, peer_event_queue);
            xpc_connection_set_context(peer, peer_event_queue);
            xpc_connection_set_finalizer_f(peer, (xpc_finalizer_t)&dispatch_release);
            
            xpc_connection_set_event_handler(peer, ^(xpc_object_t nevent) {
                xpc_type_t ntype = xpc_get_type(nevent);
                
                if (ntype == XPC_TYPE_ERROR && nevent == XPC_ERROR_CONNECTION_INVALID)
                    dispatch_release(peer_event_queue);
                if (ntype != XPC_TYPE_DICTIONARY)
                    return;
                
                xpc_dictionary_apply(nevent, ^bool(const char *key, xpc_object_t value) {
                    NSAutoreleasePool *localPool = [[NSAutoreleasePool alloc] init];
                    
                    if (0 == strcmp(key, SUDownloadServiceDidBeginDownloadingKey))
                    {
                        if ([_delegate respondsToSelector:@selector(downloadDidBegin:)])
                        {
                            void (^block)(void) = ^ {
                                [_delegate downloadDidBegin:(NSURLDownload *)self];
                            };
                            [self performBlock:block onThread:_startedThread synchronous:NO];
                        }
                    }
                    else if (0 == strcmp(key, SUDownloadServiceReceivedResponseDataKey))
                    {
                        if ([_delegate respondsToSelector:@selector(download:didReceiveResponse:)])
                        {
                            size_t dataLength = 0;
                            const void * responseDataBytes = xpc_dictionary_get_data(nevent, SUDownloadServiceReceivedResponseDataKey, &dataLength);
                            NSData *responseData = [NSData dataWithBytes:responseDataBytes length:(NSUInteger)dataLength];
                            
                            NSURLResponse *response = [NSKeyedUnarchiver unarchiveObjectWithData:responseData];
                            void (^block)(void) = ^ {
                                [_delegate download:(NSURLDownload *)self didReceiveResponse:response];
                            };
                            [self performBlock:block onThread:_startedThread synchronous:NO];
                        }
                    }
                    else if (0 == strcmp(key, SUDownloadServiceReceivedDataLengthKey))
                    {
                        if ([_delegate respondsToSelector:@selector(download:didReceiveDataOfLength:)])
                        {
                            int64_t dataLength = xpc_dictionary_get_int64(nevent, SUDownloadServiceReceivedDataLengthKey);
                            void (^block)(void) = ^ {
                                [_delegate download:(NSURLDownload *)self didReceiveDataOfLength:(NSUInteger)dataLength];
                            };
                            [self performBlock:block onThread:_startedThread synchronous:NO];
                        }
                    }
                    else if (0 == strcmp(key, SUDownloadServiceCreatedDestinationPathKey))
                    {
                        [_connectionDestination release];
                        _connectionDestination = [[NSString alloc] initWithCString:xpc_dictionary_get_string(nevent, SUDownloadServiceCreatedDestinationPathKey)
                                                                          encoding:NSUTF8StringEncoding];
                    }
                    else if (0 == strcmp(key, SUDownloadServiceReceivedFailErrorKey))
                    {
                        size_t dataLength = 0;
                        const void * errorDataBytes = xpc_dictionary_get_data(nevent, SUDownloadServiceReceivedFailErrorKey, &dataLength);
                        NSData *errorData = [NSData dataWithBytes:errorDataBytes length:dataLength];
                        
                        NSError *error = [NSKeyedUnarchiver unarchiveObjectWithData:errorData];
                        _downloadError = [error retain];
                    }
                    else if (0 == strcmp(key, SUDownloadServiceDidFinishDownloadingKey))
                    {
                        NSFileManager *fileManager = [NSFileManager defaultManager];
                        
                        NSString *destPath = _destination;
                        if ([destPath isEqualToString:[destPath lastPathComponent]])
                        {
                            destPath = _connectionDestination;
                        }
                        else if (!_allowOverwrite)
                        {
                            NSUInteger index = 1;
                            NSString *parentFolder = [destPath stringByDeletingLastPathComponent];
                            NSString *initialFileName = [[destPath lastPathComponent] stringByDeletingPathExtension];
                            NSString *fileExtension = [destPath pathExtension];

                            while ([fileManager fileExistsAtPath:destPath])
                            {
                                NSString *fileName = [initialFileName stringByAppendingFormat:@"_%ld", index];
                                destPath = [[parentFolder stringByAppendingPathComponent:fileName] stringByAppendingPathExtension:fileExtension];
                                ++index;
                            }
                        }
                        
                        NSError *error = nil;
                        BOOL success = YES;
                        
                        if (![destPath isEqualToString:_connectionDestination])
                        {
                            success = success && [fileManager createDirectoryAtPath:[destPath stringByDeletingLastPathComponent]
                                                        withIntermediateDirectories:YES
                                                                         attributes:nil
                                                                              error:&error];
                            if (success && [fileManager fileExistsAtPath:destPath])
                                success = [fileManager removeItemAtPath:destPath error:&error];
                            success = success && [fileManager moveItemAtPath:_connectionDestination toPath:destPath error:&error];
                        }
                        
                        if (success)
                        {
                            void (^block)(void) = ^ {
                                if ([_delegate respondsToSelector:@selector(download:didCreateDestination:)])
                                    [_delegate download:(NSURLDownload *)self didCreateDestination:destPath];
                                
                                if ([_delegate respondsToSelector:@selector(downloadDidFinish:)])
                                    [_delegate downloadDidFinish:(NSURLDownload *)self];
                            };
                            [self performBlock:block onThread:_startedThread synchronous:NO];
                        }
                        else
                        {
                            _downloadError = [error retain];
                        }
                    }
                    
                    [localPool release];
                    
                    return true;
                });
            });
            xpc_connection_resume(peer);
        } 
    });
    
    // Need to resume the service in order for it to process messages.
    xpc_connection_resume(_delegateConnection);
    xpc_connection_resume(_connection);
    return _connection;
}

#pragma mark - Private

- (void)performBlock:(void (^)(void))block onThread:(NSThread *)thread synchronous:(BOOL)flag
{
    void (^blockCopy)(void) = block != NULL ? Block_copy(block) : NULL;
    [self performSelector:@selector(fireBlock:) onThread:thread withObject:blockCopy waitUntilDone:flag];
}

- (void)fireBlock:(void (^)(void))block
{
    if (NULL == block)
        return;
    
    block();
    Block_release(block);
}

@end
