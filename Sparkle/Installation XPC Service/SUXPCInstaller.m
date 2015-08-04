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
#import "SUCodeSigningVerifier.h"

BOOL SUShouldUseXPCInstaller(void)
{
    if (![SUCodeSigningVerifier hostApplicationIsSandboxed])
        return NO;
    
    NSString *xpcServicePrefixPath = [[NSBundle mainBundle] bundlePath];
    NSString *xpcServiceSuffixPath = @"Contents/XPCServices/com.devmate.UpdateInstaller.xpc";
    return [[NSFileManager defaultManager] fileExistsAtPath:[xpcServicePrefixPath stringByAppendingPathComponent:xpcServiceSuffixPath]];
}

@implementation SUXPCInstaller

+ (xpc_connection_t)getSandboxXPCService
{
    __block xpc_connection_t serviceConnection = xpc_connection_create("com.devmate.UpdateInstaller", dispatch_get_main_queue());
    
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

+ (BOOL)copyPathWithAuthentication:(NSString *)src overPath:(NSString *)dst appendVersion:(BOOL)appendVersion error:(NSError *__autoreleasing *)outError
{
    xpc_connection_t connection = [self getSandboxXPCService];

	xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_int64(message, SUInstallServiceTaskTypeKey, (int64_t)SUInstallServiceTaskAuthCopyPath);
	
	if (src)
		xpc_dictionary_set_string(message, SUInstallServiceSourcePathKey, [src fileSystemRepresentation]);
	if (dst)
		xpc_dictionary_set_string(message, SUInstallServiceDestinationPathKey, [dst fileSystemRepresentation]);
    xpc_dictionary_set_bool(message, SUInstallServiceAppendVersionKey, appendVersion ? true : false);
	
    __block BOOL xpcDidReply = NO;
    __block NSError *error = nil;
    
    dispatch_queue_t queue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
    xpc_connection_send_message_with_reply(connection, message, queue, ^(xpc_object_t response) {
        if (XPC_TYPE_ERROR == xpc_get_type(response))
        {
            NSDictionary *errorInfo = [NSDictionary dictionaryWithObject:@"Internal XPC error."
                                                                  forKey:NSLocalizedDescriptionKey];
            error = [[NSError alloc] initWithDomain:SUSparkleErrorDomain code:SUXPCServiceError userInfo:errorInfo];
        }
        else if (XPC_TYPE_DICTIONARY == xpc_get_type(response))
        {
            const char *errorString = xpc_dictionary_get_string(response, SUInstallServiceErrorLocalizedDescriptionKey);
            if (errorString != NULL)
            {
                NSDictionary *errorInfo = [NSDictionary dictionaryWithObject:[NSString stringWithCString:errorString encoding:NSUTF8StringEncoding]
                                                                      forKey:NSLocalizedDescriptionKey];
                error = [[NSError alloc] initWithDomain:SUSparkleErrorDomain code:SUXPCServiceError userInfo:errorInfo];
            }
        }
        
        xpcDidReply = YES;
    });
    
    while (NO == xpcDidReply)
    {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    }
    
    xpc_release(message);
    dispatch_release(queue);
    
    if (nil != error && NULL != outError)
    {
        *outError = error;
    }
    
    return (nil == error);
}

+ (BOOL)copyPathContent:(NSString *)src toDirectory:(NSString *)dstDir error:(NSError * __autoreleasing*)outError
{
    xpc_connection_t connection = [self getSandboxXPCService];
    
	xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_int64(message, SUInstallServiceTaskTypeKey, (int64_t)SUInstallServiceTaskCopyPath);
	
	if (src)
		xpc_dictionary_set_string(message, SUInstallServiceSourcePathKey, [src fileSystemRepresentation]);
	if (dstDir)
		xpc_dictionary_set_string(message, SUInstallServiceDestinationPathKey, [dstDir fileSystemRepresentation]);
	
    __block BOOL xpcDidReply = NO;
    __block NSError *error = nil;
    
    dispatch_queue_t queue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
    xpc_connection_send_message_with_reply(connection, message, queue, ^(xpc_object_t response) {
        if (XPC_TYPE_ERROR == xpc_get_type(response))
        {
            NSDictionary *errorInfo = [NSDictionary dictionaryWithObject:@"Internal XPC error."
                                                                  forKey:NSLocalizedDescriptionKey];
            error = [[NSError alloc] initWithDomain:SUSparkleErrorDomain code:SUXPCServiceError userInfo:errorInfo];
        }
        else if (XPC_TYPE_DICTIONARY == xpc_get_type(response))
        {
            const char *errorString = xpc_dictionary_get_string(response, SUInstallServiceErrorLocalizedDescriptionKey);
            if (errorString != NULL)
            {
                NSDictionary *errorInfo = [NSDictionary dictionaryWithObject:[NSString stringWithCString:errorString encoding:NSUTF8StringEncoding]
                                                                      forKey:NSLocalizedDescriptionKey];
                error = [[NSError alloc] initWithDomain:SUSparkleErrorDomain code:SUXPCServiceError userInfo:errorInfo];
            }
        }
        
        xpcDidReply = YES;
    });
    
    while (NO == xpcDidReply)
    {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
    }
    
    xpc_release(message);
    dispatch_release(queue);
    
    if (nil != error && NULL != outError)
    {
        *outError = error;
    }
    
    return (nil == error);
}

+ (void)launchTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)arguments
{
    [self launchTaskWithPath:path
                   arguments:arguments
                 environment:nil
        currentDirectoryPath:nil
                   inputData:nil
           waitForTaskResult:NO
               waitUntilDone:YES
           completionHandler:nil];
}

+ (void)launchTaskWithPath:(NSString *)launchPath
                 arguments:(NSArray *)arguments
               environment:(NSDictionary *)environment
      currentDirectoryPath:(NSString *)currentDirPath
                 inputData:(NSData *)inputData
         waitForTaskResult:(BOOL)waitForTaskResult
             waitUntilDone:(BOOL)waitUntilDone
         completionHandler:(void (^)(int result, NSData *outputData))completionHandler
{
    xpc_connection_t connection = [self getSandboxXPCService];
    
    xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_int64(message, SUInstallServiceTaskTypeKey, (int64_t)SUInstallServiceTaskLaunchTask);
    
    if ([launchPath length])
    {
		xpc_dictionary_set_string(message, SUInstallServiceLaunchTaksPathKey, [launchPath fileSystemRepresentation]);
    }
    
    if ([arguments count])
    {
        xpc_object_t array = xpc_array_create(NULL, 0);
        for (id argument in arguments)
        {
            NSString *strArgument = argument;
            if (![strArgument isKindOfClass:[NSString class]])
                strArgument = [argument description];
            
            xpc_array_set_string(array, XPC_ARRAY_APPEND, [strArgument UTF8String]);
        }
        xpc_dictionary_set_value(message, SUInstallServiceLaunchTaskArgumentsKey, array);
        xpc_release(array);
    }
    
    if ([environment count])
    {
        __block xpc_object_t dict = xpc_dictionary_create(NULL, NULL, 0);
        [environment enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL __unused *stop) {
            NSString *xpc_key = [key isKindOfClass:[NSString class]] ? key : [key description];
            NSString *xpc_value = [obj isKindOfClass:[NSString class]] ? obj : [obj description];
            
            xpc_dictionary_set_string(dict, [xpc_key UTF8String], [xpc_value UTF8String]);
        }];
        
        xpc_dictionary_set_value(message, SUInstallServiceLaunchTaskEnvironmentKey, dict);
        xpc_release(dict);
    }
    
    if ([currentDirPath length])
    {
		xpc_dictionary_set_string(message, SUInstallServiceLaunchTaskCurrentDirKey, [currentDirPath fileSystemRepresentation]);
    }
    
    if ([inputData length])
    {
        xpc_dictionary_set_data(message, SUInstallServiceLaunchTaskInputDataKey, [inputData bytes], [inputData length]);
    }
    
    xpc_dictionary_set_bool(message, SUInstallServiceLaunchTaskReplyImmediatelyKey, waitForTaskResult ? false : true);
    
    __block BOOL xpcTaskDidReply = NO;
    xpc_connection_send_message_with_reply(connection, message, dispatch_get_current_queue(), ^(xpc_object_t response) {
        int taskResult = 0;
        NSData *outputData = nil;
        
        if (completionHandler != NULL)
        {
            xpc_type_t type = xpc_get_type(response);
            if (type == XPC_TYPE_ERROR)
            {
                taskResult = SUXPCServiceError;
            }
            else if (type == XPC_TYPE_DICTIONARY)
            {
                taskResult = (int)xpc_dictionary_get_int64(response, SUInstallServiceErrorCodeKey);
                
                size_t bytesLen = 0;
                const void *bytes = xpc_dictionary_get_data(response, SUInstallServiceLaunchTaskOutputDataKey, &bytesLen);
                if (NULL != bytes)
                {
                    outputData = [NSData dataWithBytes:bytes length:bytesLen];
                }
            }

            completionHandler(taskResult, outputData);
        }
        
        xpcTaskDidReply = YES;
    });
    xpc_release(message);
    
    if (waitUntilDone)
    {
        while (NO == xpcTaskDidReply)
        {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
        }
    }
}

@end
