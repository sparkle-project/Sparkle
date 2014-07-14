//
//  main.m
//  Update
//
//  Created by Whitney Young on 3/19/12.
//  Copyright (c) 2012 FadingRed. All rights reserved.
//

#include <xpc/xpc.h>
#include <asl.h>

#import <Foundation/Foundation.h>
#import "SUPlainInstallerInternals.h"
#import "SUInstallServiceConstants.h"
#import "SULog.h"
#import "SUConstants.h"

static xpc_object_t SUSICopyPathContent(xpc_object_t message)
{
    if (NULL == message)
        return NULL;
    
    const char *src = xpc_dictionary_get_string(message, SUInstallServiceSourcePathKey);
    const char *dst = xpc_dictionary_get_string(message, SUInstallServiceDestinationPathKey);
    
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *sourcePath = src ? [manager stringWithFileSystemRepresentation:src length:strlen(src)] : nil;
    NSString *targetPath = dst ? [manager stringWithFileSystemRepresentation:dst length:strlen(dst)] : nil;

    NSError *error = nil;
    do
    {
        if (nil == sourcePath)
        {
            NSDictionary *errorInfo = [NSDictionary dictionaryWithObject:@"Source path is absent." forKey:NSLocalizedDescriptionKey];
            error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUXPCServiceError userInfo:errorInfo];
            break;
        }
        
        if (nil == targetPath)
        {
            NSDictionary *errorInfo = [NSDictionary dictionaryWithObject:@"Destination path is absent." forKey:NSLocalizedDescriptionKey];
            error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUXPCServiceError userInfo:errorInfo];
            break;
        }
        
        NSArray *contents = nil;
        
        BOOL isSrcDirectory = NO;
        BOOL isSrcExist = [manager fileExistsAtPath:sourcePath isDirectory:&isSrcDirectory];
        isSrcDirectory = isSrcDirectory && ![[NSWorkspace sharedWorkspace] isFilePackageAtPath:sourcePath];
        if (isSrcExist && isSrcDirectory)
        {
            contents = [manager contentsOfDirectoryAtPath:sourcePath error:&error];
        }
        else if (isSrcExist)
        {
            contents = [NSArray arrayWithObject:@""];
        }
        else
        {
            NSDictionary *errorInfo = [NSDictionary dictionaryWithObject:@"Source does not exist on disk." forKey:NSLocalizedDescriptionKey];
            error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUXPCServiceError userInfo:errorInfo];
        }
        
        if (nil != error)
        {
            break;
        }

        BOOL isDstDirectory = NO;
        BOOL isDstExist = [manager fileExistsAtPath:targetPath isDirectory:&isDstDirectory];
        if (isSrcDirectory && (!isDstExist || !isDstDirectory))
        {
            if (isDstExist)
                [manager removeItemAtPath:targetPath error:&error];
            [manager createDirectoryAtPath:targetPath withIntermediateDirectories:YES attributes:nil error:&error];
        }
        else if (!isSrcDirectory)
        {
            if (isDstExist && !isDstDirectory)
                [manager removeItemAtPath:targetPath error:&error];
            [manager createDirectoryAtPath:targetPath withIntermediateDirectories:YES attributes:nil error:&error];
        }
        
        if (nil != error)
        {
            break;
        }
        
        for (NSString *item in contents)
        {
            NSString *fromPath = [item length] ? [sourcePath stringByAppendingPathComponent:item] : sourcePath;
            NSString *toPath = [item length] ? [targetPath stringByAppendingPathComponent:item] : [targetPath stringByAppendingPathComponent:[sourcePath lastPathComponent]];
            
            if (![manager isReadableFileAtPath:fromPath])
            {
                SULog(@"XPC Install Service: will skip \"%@\"", fromPath);
                continue;
            }

            SULog(@"XPC Install Service: will copy \"%@\" to \"%@\"", fromPath, toPath);

            if ([manager fileExistsAtPath:toPath])
                [manager removeItemAtPath:toPath error:&error];
            
            if (![manager copyItemAtPath:fromPath toPath:toPath error:&error])
                break;
        }
    }
    while (NO);
    
    xpc_object_t reply = xpc_dictionary_create_reply(message);
    if (nil != error)
    {
        xpc_dictionary_set_int64(reply, SUInstallServiceErrorCodeKey, (int64_t)[error code]);
        const char *errorMsg = [[error localizedDescription] length] ? [[error localizedDescription] UTF8String] : "";
        xpc_dictionary_set_string(reply, SUInstallServiceErrorLocalizedDescriptionKey, errorMsg);
    }
    
    return reply;
}

static xpc_object_t SUISCopyPathWithAuthentication(xpc_object_t message)
{
    if (NULL == message)
        return NULL;
    
    const char *src = xpc_dictionary_get_string(message, SUInstallServiceSourcePathKey);
    const char *dst = xpc_dictionary_get_string(message, SUInstallServiceDestinationPathKey);
    const char *tmp = xpc_dictionary_get_string(message, SUInstallServiceTempNameKey);
    
    NSFileManager *manager = [NSFileManager defaultManager];
    NSString *relaunchPathToCopy = src ? [manager stringWithFileSystemRepresentation:src length:strlen(src)] : nil;
    NSString *targetPath = dst ? [manager stringWithFileSystemRepresentation:dst length:strlen(dst)] : nil;
    NSString *temporaryName = tmp ? [NSString stringWithUTF8String:tmp] : nil;
    NSError *error = nil;
    BOOL result = [SUPlainInstaller copyPathWithAuthentication:relaunchPathToCopy overPath:targetPath temporaryName:temporaryName error:&error];
    
    // send response to indicate ok
    xpc_object_t reply = xpc_dictionary_create_reply(message);
    if (!result && error != nil)
    {
        xpc_dictionary_set_int64(reply, SUInstallServiceErrorCodeKey, (int64_t)[error code]);
        const char *errorMsg = [[error localizedDescription] length] ? [[error localizedDescription] UTF8String] : "";
        xpc_dictionary_set_string(reply, SUInstallServiceErrorLocalizedDescriptionKey, errorMsg);
    }
    
    return reply;
}

static xpc_object_t SUISLaunchTask(xpc_object_t message)
{
    if (NULL == message)
        return NULL;
    
    const char *path = xpc_dictionary_get_string(message, SUInstallServiceLaunchTaksPathKey);
    NSString *launchPath = path ? [[NSFileManager defaultManager] stringWithFileSystemRepresentation:path length:strlen(path)] : nil;
    
    xpc_object_t array = xpc_dictionary_get_value(message, SUInstallServiceLaunchTaskArgumentsKey);
    NSArray *arguments = nil;
    if (NULL != array)
    {
        size_t count = xpc_array_get_count(array);
        NSMutableArray *mutableArgs = [NSMutableArray arrayWithCapacity:count];
        for (size_t i = 0; i < count; i++)
        {
            [mutableArgs addObject:[NSString stringWithUTF8String:xpc_array_get_string(array, i)]];
        }
        
        arguments = mutableArgs;
    }
    
    xpc_object_t dict = xpc_dictionary_get_value(message, SUInstallServiceLaunchTaskEnvironmentKey);
    NSDictionary *environment = nil;
    if (NULL != dict)
    {
        size_t count = xpc_dictionary_get_count(dict);
        __block NSMutableDictionary *mutableEnv = [NSMutableDictionary dictionaryWithCapacity:count];
        
        xpc_dictionary_apply(dict, ^bool(const char *key, xpc_object_t value) {
            NSString *envKey = [NSString stringWithUTF8String:key];
            NSString *envValue = [NSString stringWithUTF8String:value];
            [mutableEnv setObject:envValue forKey:envKey];
            return true;
        });
        
        environment = mutableEnv;
    }
    
    path = xpc_dictionary_get_string(message, SUInstallServiceLaunchTaskCurrentDirKey);
    NSString *currentDirPath = path ? [[NSFileManager defaultManager] stringWithFileSystemRepresentation:path length:strlen(path)] : nil;
    
    size_t bytesLen = 0;
    const void *bytes = xpc_dictionary_get_data(message, SUInstallServiceLaunchTaskInputDataKey, &bytesLen);
    NSData *inputData = bytes ? [NSData dataWithBytes:bytes length:bytesLen] : nil;
    
    bool shouldReplyImmediatly = xpc_dictionary_get_bool(message, SUInstallServiceLaunchTaskReplyImmediatelyKey);
    
    // prepare NSTask
    NSTask *task = [[[NSTask alloc] init] autorelease];
    NSPipe *inputPipe = [NSPipe pipe];
    NSPipe *outputPipe = [NSPipe pipe];
    
    [task setStandardInput:inputPipe];
    [task setStandardOutput:outputPipe];
    [task setStandardError:outputPipe];
    
    if (launchPath != nil)
        [task setLaunchPath:launchPath];
    if ([arguments count])
        [task setArguments:arguments];
    if ([environment count])
        [task setEnvironment:environment];
    if (currentDirPath != nil)
        [task setCurrentDirectoryPath:currentDirPath];
    
    __block NSData *outputData = nil;
    __block int taskResult = 0;
    __block BOOL isTaskRunning = YES;
    
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    NSArray *notificationObjects = nil;
    
    if (!shouldReplyImmediatly)
    {
        id object1 = [notificationCenter addObserverForName:NSFileHandleReadToEndOfFileCompletionNotification
                                                     object:[outputPipe fileHandleForReading]
                                                      queue:[NSOperationQueue mainQueue]
                                                 usingBlock:^(NSNotification *note) {
                                                     outputData = [[[note userInfo] objectForKey:NSFileHandleNotificationDataItem] retain];
                                                     isTaskRunning = NO;
                                                 }];
        
        id object2 = [notificationCenter addObserverForName:NSTaskDidTerminateNotification
                                                     object:task
                                                      queue:[NSOperationQueue mainQueue]
                                                 usingBlock:^(NSNotification *note) {
                                                     taskResult = [task terminationStatus];
                                                 }];
        
        notificationObjects = [NSArray arrayWithObjects:object1, object2, nil];
    }
    
    [[outputPipe fileHandleForReading] readToEndOfFileInBackgroundAndNotifyForModes:[NSArray arrayWithObject:NSDefaultRunLoopMode]];
    
    @try
    {
        [task launch];
        
        if ([inputData length])
        {
            [[inputPipe fileHandleForWriting] writeData:inputData];
            [[inputPipe fileHandleForWriting] closeFile];
        }
        
        if (!shouldReplyImmediatly)
        {
            // loop until we are done receiving the data
            while (YES == isTaskRunning)
            {
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, true);
            }
        }
    }
    @catch (...)
    {
        taskResult = SUXPCServiceError;
    }
    
    // send response to indicate ok
    xpc_object_t reply = xpc_dictionary_create_reply(message);
    xpc_dictionary_set_int64(reply, SUInstallServiceErrorCodeKey, (int64_t)taskResult);
    if (outputData != nil)
    {
        xpc_dictionary_set_data(reply, SUInstallServiceLaunchTaskOutputDataKey, [outputData bytes], [outputData length]);
    }
    
    for (id object in notificationObjects)
    {
        [notificationCenter removeObserver:object];
    }
    [outputData release];
    
    return reply;
}

static void peer_event_handler(xpc_connection_t peer, xpc_object_t event)
{
	xpc_type_t type = xpc_get_type(event);
	if (type == XPC_TYPE_ERROR)
    {
		if (event == XPC_ERROR_CONNECTION_INVALID)
        {
			// The client process on the other end of the connection has either
			// crashed or cancelled the connection. After receiving this error,
			// the connection is in an invalid state, and you do not need to
			// call xpc_connection_cancel(). Just tear down any associated state
			// here.
		}
        else if (event == XPC_ERROR_TERMINATION_IMMINENT)
        {
			// Handle per-connection termination cleanup.
		}
	}
    else if (type == XPC_TYPE_DICTIONARY)
    {
		// Handle the message.
		SUInstallServiceTask task = (SUInstallServiceTask)xpc_dictionary_get_int64(event, SUInstallServiceTaskTypeKey);
        
        NSLog(@"XPC Installer: should start task with id = %lld", (int64_t)task);
        
        xpc_object_t reply = NULL;

        NSAutoreleasePool *localPool = [[NSAutoreleasePool alloc] init];
        switch (task)
        {
            case SUInstallServiceTaskCopyPath:
            {
                reply = SUSICopyPathContent(event);
                break;
            }
                
            case SUInstallServiceTaskAuthCopyPath:
            {
                reply = SUISCopyPathWithAuthentication(event);
                break;
            }
                
            case SUInstallServiceTaskLaunchTask:
            {
                reply = SUISLaunchTask(event);
                break;
            }
                
            default:
            {
                SULog(@"XPC Install Service: Unknown XPC service task %lld", (int64_t)task);
                
                reply = xpc_dictionary_create_reply(event);
                xpc_dictionary_set_int64(reply, SUInstallServiceErrorCodeKey, (int64_t)SUXPCServiceError);
                xpc_dictionary_set_string(reply, SUInstallServiceErrorLocalizedDescriptionKey, "Unknown install cervice task.");
                
                break;
            }
		}
        [localPool release];
        
        if (NULL == reply)
        {
            reply = xpc_dictionary_create_reply(event);
        }
        
        xpc_connection_send_message(peer, reply);
        xpc_release(reply);
	}
}

static void event_handler(xpc_connection_t peer)
{
	// By defaults, new connections will target the default dispatch
	// concurrent queue.
	xpc_connection_set_event_handler(peer, ^(xpc_object_t event) {
		peer_event_handler(peer, event);
	});
	
	// This will tell the connection to begin listening for events. If you
	// have some other initialization that must be done asynchronously, then
	// you can defer this call until after that initialization is done.
	xpc_connection_resume(peer);
}

int main(int argc, const char *argv[])
{
	xpc_main(event_handler);
	return 0;
}
