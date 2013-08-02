//
//  SUXPCInstaller.m
//  Sparkle
//
//  Created by Whitney Young on 3/19/12.
//  Copyright (c) 2012 FadingRed. All rights reserved.
//

#import <xpc/xpc.h>
#import "SUXPCInstaller.h"
#import "SUInstallServiceConstants.h"


@implementation SUXPCInstaller

+ (xpc_connection_t)getSandboxXPCService
{
    __block xpc_connection_t serviceConnection = xpc_connection_create("com.andymatuschak.Sparkle.install-service", dispatch_get_main_queue());
    
    if (!serviceConnection)
    {
        NSLog(@"Can't connect to XPC service");
        return (NULL);
    }
    
    xpc_connection_set_event_handler(serviceConnection, ^(xpc_object_t event) {
        xpc_type_t type = xpc_get_type(event);
        
        if (type == XPC_TYPE_ERROR)
        {
            if (event == XPC_ERROR_CONNECTION_INVALID)
            {
                // The service is invalid. Either the service name supplied to
                // xpc_connection_create() is incorrect or we (this process) have
                // canceled the service; we can do any cleanup of appliation
                // state at this point.
                xpc_release(serviceConnection);
            }
        }
    });
    
    // Need to resume the service in order for it to process messages.
    xpc_connection_resume(serviceConnection);
    return (serviceConnection);
}

+ (void)copyPathWithAuthentication:(NSString *)src overPath:(NSString *)dst temporaryName:(NSString *)tmp completionHandler:(void (^)(NSError *error))completionHandler
{
    xpc_connection_t connection = [self getSandboxXPCService];

	xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_int64(message, SUInstallServiceTaskTypeKey, (int64_t)SUInstallServiceTaskCopyPath);
	
	if (src)
		xpc_dictionary_set_string(message, SUInstallServiceSourcePathKey, [src fileSystemRepresentation]);
	if (dst)
		xpc_dictionary_set_string(message, SUInstallServiceDestinationPathKey, [dst fileSystemRepresentation]);
	if (tmp)
		xpc_dictionary_set_string(message, SUInstallServiceTempNameKey, [tmp UTF8String]);
	
    xpc_connection_send_message_with_reply(connection, message, dispatch_get_main_queue(), ^(xpc_object_t response) {
        if (NULL == completionHandler)
            return;
        
        const char *errorString = xpc_dictionary_get_string(response, SUInstallServiceErrorLocalizedDescriptionKey);
        if (errorString != NULL)
        {
            NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain
                                                 code:SUXPCServiceError
                                             userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithCString:errorString encoding:NSUTF8StringEncoding]
                                                                                  forKey:NSLocalizedDescriptionKey]];
            completionHandler(error);
        }
        else
        {
            completionHandler(nil);
        }
    });
    xpc_release(message);
}

+ (void)launchTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)arguments completionHandler:(void (^)(void))completionHandler
{
    xpc_connection_t connection = [self getSandboxXPCService];
	
	xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_int64(message, SUInstallServiceTaskTypeKey, (int64_t)SUInstallServiceTaskLaunchTask);
	
	if (path)
		xpc_dictionary_set_string(message, SUInstallServiceLaunchTaksPathKey, [path fileSystemRepresentation]);
	
	xpc_object_t array = xpc_array_create(NULL, 0);
	for (id argument in arguments)
    {
        xpc_array_set_string(array, XPC_ARRAY_APPEND, [argument UTF8String]);
	}
	xpc_dictionary_set_value(message, SUInstallServiceLaunchTaskArgumentsKey, array);
    xpc_release(array);
	
    xpc_connection_send_message_with_reply(connection, message, dispatch_get_current_queue(), ^(xpc_object_t response) {
        if (completionHandler != NULL)
            completionHandler();
    });
    xpc_release(message);
}

@end
