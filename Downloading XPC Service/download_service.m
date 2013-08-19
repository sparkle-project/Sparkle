//
//  main.m
//  Downloading XPC Service
//
//  Created by Erik Aderstedt on 2012-08-09.
//  Based on the Apple sample code 'SandboxedFetch'.
//

#import <xpc/xpc.h>
#import <asl.h>
#import <assert.h>
#import <errno.h>
#import <stdio.h>

#import "SUDownloadServiceConstants.h"
#import "SUDSDownloader.h"

static void fetch_process_request(xpc_object_t request, xpc_object_t reply);
static void fetch_peer_event_handler(xpc_connection_t peer, xpc_object_t event);
static void fetch_event_handler(xpc_connection_t peer);

#pragma mark -

// Process the XPC request, create a temporary file to hold downloaded,
// data, and build/return XPC reply.
static void fetch_process_request(xpc_object_t request, xpc_object_t reply)
{
    __block int errcode = 0;
    __block const char *errmsg = NULL;
    xpc_connection_t connection = NULL;

    NSAutoreleasePool *localPool = [[NSAutoreleasePool alloc] init];
    do
    {
        size_t dataLength = 0;
        const void *data = xpc_dictionary_get_data(request, SUDownloadServiceURLRequestDataKey, &dataLength);
        NSData *requestData = [NSData dataWithBytes:data length:dataLength];
        
        NSURLRequest *urlRequest = [NSKeyedUnarchiver unarchiveObjectWithData:requestData];
        if (nil == urlRequest)
        {
            errcode = EINVAL;
            errmsg = "Invalid URL request data";
            break;
        }

        // Get the URL and XPC connection from the XPC request
        connection = xpc_dictionary_create_connection(request, SUDownloadServiceDelegateConnectionKey);
        if (connection == NULL)
        {
            errcode = EINVAL;
            errmsg = "Invalid XPC delegate connection";
            break;
        }
        
        // Set up XPC connection endpoint for sending progress reports and receiving cancel notification.
        __block BOOL shouldStopDownload = NO;
        xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
            xpc_type_t type = xpc_get_type(event);

            // If the remote end of this connection has gone away then stop download
            if (XPC_TYPE_ERROR == type &&
                (XPC_ERROR_CONNECTION_INTERRUPTED == event || XPC_ERROR_CONNECTION_INVALID == event))
            {
                asl_log(NULL, NULL, ASL_LEVEL_NOTICE, "Stopping download process...\n");
                shouldStopDownload = YES;
            }
        });
        xpc_connection_resume(connection);

        NSString *destinationPath = [NSString stringWithCString:xpc_dictionary_get_string(request, SUDownloadServiceFilePathKey)
                                                encoding:NSUTF8StringEncoding];
        SUDSDownloader *downloader = [SUDSDownloader downloaderWithURLRequest:urlRequest
                                                              destinationPath:destinationPath];
        
        SUDSDownloaderCallBacks callBacks = {0};
        
        callBacks.downloadDidReceiveData = ^(SUDSDownloader *downloader, NSUInteger dataLength) {
            xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
            xpc_dictionary_set_int64(message, SUDownloadServiceReceivedDataLengthKey, (int64_t)dataLength);
            xpc_object_t answer = xpc_connection_send_message_with_reply_sync(connection, message);
            xpc_release(message);
            xpc_release(answer);
        };
        
        callBacks.downloadDidReceiveResponse = ^(SUDSDownloader *downloader, NSURLResponse *response) {
            NSData *responseData = [NSKeyedArchiver archivedDataWithRootObject:response];
            
            xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
            xpc_dictionary_set_data(message, SUDownloadServiceReceivedResponseDataKey, [responseData bytes], [responseData length]);
            xpc_object_t answer = xpc_connection_send_message_with_reply_sync(connection, message);
            xpc_release(message);
            xpc_release(answer);
        };
        
        callBacks.downloadDidCreateDestination = ^(SUDSDownloader *downloader, NSString *destinationPath) {
            xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
            xpc_dictionary_set_string(message, SUDownloadServiceCreatedDestinationPathKey, [destinationPath cStringUsingEncoding:NSUTF8StringEncoding]);
            xpc_object_t answer = xpc_connection_send_message_with_reply_sync(connection, message);
            xpc_release(message);
            xpc_release(answer);
        };
        
        callBacks.downloadDidBegin = ^(SUDSDownloader *downloader) {
            xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
            xpc_dictionary_set_bool(message, SUDownloadServiceDidBeginDownloadingKey, true);
            xpc_object_t answer = xpc_connection_send_message_with_reply_sync(connection, message);
            xpc_release(message);
            xpc_release(answer);
        };
        
        callBacks.downloadDidFail = ^(SUDSDownloader *downloader, NSError *error) {
            errcode = (int)[error code];
            errmsg = [[error localizedDescription] cStringUsingEncoding:NSUTF8StringEncoding];
            
            NSData *errorData = [NSKeyedArchiver archivedDataWithRootObject:error];
            
            xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
            xpc_dictionary_set_data(message, SUDownloadServiceReceivedFailErrorKey, [errorData bytes], [errorData length]);
            xpc_object_t answer = xpc_connection_send_message_with_reply_sync(connection, message);
            xpc_release(message);
            xpc_release(answer);
        };
        
        callBacks.downloadDidFinish = ^(SUDSDownloader *downloader) {
            xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
            xpc_dictionary_set_bool(message, SUDownloadServiceDidFinishDownloadingKey, true);
            xpc_object_t answer = xpc_connection_send_message_with_reply_sync(connection, message);
            xpc_release(message);
            xpc_release(answer);
        };
        
        callBacks.downloadShouldDecodeSourceData = ^BOOL(SUDSDownloader *downloader, NSString *MIMEType) {
            xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
            xpc_dictionary_set_string(message, SUDownloadServiceMIMETypeToDecodeKey, [MIMEType cStringUsingEncoding:NSUTF8StringEncoding]);
            xpc_object_t answer = xpc_connection_send_message_with_reply_sync(connection, message);
            xpc_release(message);
            
            BOOL result = NO;
            if (xpc_get_type(answer) == XPC_TYPE_DICTIONARY)
                result = (BOOL)xpc_dictionary_get_bool(answer, SUDownloadServiceShouldDecodeMIMETypeKey);
            xpc_release(answer);
            
            return result;
        };
        
        [downloader setCallBacks:callBacks];
        
        [downloader startDownload];
        while ([downloader isInProgress])
        {
            if (shouldStopDownload)
            {
                [downloader stopDownload];
                asl_log(NULL, NULL, ASL_LEVEL_NOTICE, "Download process stopped.\n");
                break;
            }
            
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, true);
        }
    }
    while (NO);
    [localPool release];
    
#if DEBUG_LOGGING_ENABLED
    NSLog(@"Download process finished. Will send last message...");
#endif
    // Clean up and add errcode/errmsg to reply
    if (connection)
    {
        xpc_connection_suspend(connection);
        xpc_release(connection);
    }

    xpc_dictionary_set_int64(reply, SUDownloadServiceErrorCodeKey, (int64_t)errcode);
    if (errmsg)
    {
        xpc_dictionary_set_string(reply, SUDownloadServiceErrorMessageKey, errmsg);
    }
}

static void fetch_peer_event_handler(xpc_connection_t peer, xpc_object_t event)
{
    // Get the object type.
    xpc_type_t type = xpc_get_type(event);
    if (XPC_TYPE_ERROR == type)
    {
        // Handle an error.
        if (XPC_ERROR_CONNECTION_INVALID == event)
        {
            // The client process on the other end of the connection
            // has either crashed or cancelled the connection.
            asl_log(NULL, NULL, ASL_LEVEL_NOTICE, "peer(%d) received "
                    "XPC_ERROR_CONNECTION_INVALID",
                    xpc_connection_get_pid(peer));
            xpc_connection_cancel(peer);
        }
        else if (XPC_ERROR_TERMINATION_IMMINENT == event)
        {
            // Handle per-connection termination cleanup. This
            // service is about to exit.
            asl_log(NULL, NULL, ASL_LEVEL_NOTICE, "peer(%d) received "
                    "XPC_ERROR_TERMINATION_IMMINENT",
                    xpc_connection_get_pid(peer));
        }
    }
    else if (XPC_TYPE_DICTIONARY == type)
    {
        xpc_object_t requestMessage = event;
        xpc_object_t replyMessage = xpc_dictionary_create_reply(requestMessage);
        assert(replyMessage != NULL);
        
        // Process request and build a reply message.
        fetch_process_request(requestMessage, replyMessage);

        xpc_connection_send_message(peer, replyMessage);
        xpc_release(replyMessage);
    }
}

static void fetch_event_handler(xpc_connection_t peer)
{
    // Generate an unique name for the queue to handle messages from
    // this peer and create a new dispatch queue for it.
    char *queue_name = NULL;
    asprintf(&queue_name, "%s-peer-%d", "com.andymatuschak.Sparkle.download-service", xpc_connection_get_pid(peer));
    dispatch_queue_t peer_event_queue = dispatch_queue_create(queue_name, DISPATCH_QUEUE_SERIAL);
    assert(peer_event_queue != NULL);
    free(queue_name);
    
    // Set the target queue for connection.
    xpc_connection_set_target_queue(peer, peer_event_queue);
    
    // Set the handler block for connection.
    xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {
        fetch_peer_event_handler(peer, event);
    });
    
    // Enable the peer connection to receive messages.
    xpc_connection_resume(peer);
}

int main(int argc, const char *argv[])
{
    xpc_main(fetch_event_handler);
    exit(EXIT_FAILURE);
}

