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
        
        NSAutoreleasePool *localPool = [[NSAutoreleasePool alloc] init];
        switch (task)
        {
            case SUInstallServiceTaskCopyPath:
            {
                const char *src = xpc_dictionary_get_string(event, SUInstallServiceSourcePathKey);
                const char *dst = xpc_dictionary_get_string(event, SUInstallServiceDestinationPathKey);
                const char *tmp = xpc_dictionary_get_string(event, SUInstallServiceTempNameKey);
                
                NSFileManager *manager = [NSFileManager defaultManager];
                NSString *relaunchPathToCopy = src ? [manager stringWithFileSystemRepresentation:src length:strlen(src)] : nil;
                NSString *targetPath = dst ? [manager stringWithFileSystemRepresentation:dst length:strlen(dst)] : nil;
                NSString *temporaryName = tmp ? [NSString stringWithUTF8String:tmp] : nil;
                NSError *error = nil;
                BOOL result = [SUPlainInstaller copyPathWithAuthentication: relaunchPathToCopy overPath: targetPath temporaryName: temporaryName error: &error];
                
                // send response to indicate ok
                xpc_object_t reply = xpc_dictionary_create_reply(event);
                if (!result && error != nil)
                {
                    xpc_dictionary_set_int64(reply, SUInstallServiceErrorCodeKey, [error code]);
                    xpc_dictionary_set_string(reply, SUInstallServiceErrorLocalizedDescriptionKey, [[error localizedDescription] cStringUsingEncoding:NSUTF8StringEncoding]);
                }
                xpc_connection_send_message(peer, reply);
                xpc_release(reply);
                
                break;
            }
                
            case SUInstallServiceTaskLaunchTask:
            {
                const char *path = xpc_dictionary_get_string(event, SUInstallServiceLaunchTaksPathKey);
                xpc_object_t array = xpc_dictionary_get_value(event, SUInstallServiceLaunchTaskArgumentsKey);

                NSFileManager *manager = [NSFileManager defaultManager];
                NSString *relaunchToolPath = path ? [manager stringWithFileSystemRepresentation:path length:strlen(path)] : nil;;
                NSMutableArray *arguments = [NSMutableArray array];
                for (size_t i = 0; i < xpc_array_get_count(array); i++)
                {
                    [arguments addObject:[NSString stringWithUTF8String:xpc_array_get_string(array, i)]];
                }
                
                [NSTask launchedTaskWithLaunchPath:relaunchToolPath arguments:arguments];
                
                // send response to indicate ok
                xpc_object_t reply = xpc_dictionary_create_reply(event);
                xpc_connection_send_message(peer, reply);
                xpc_release(reply);
                
                break;
            }
                
            default:
            {
                SULog(@"XPC Install Service: Unknown XPC service task %lld", (int64_t)task);
                
                xpc_object_t reply = xpc_dictionary_create_reply(event);
                xpc_dictionary_set_int64(reply, SUInstallServiceErrorCodeKey, (int64_t)1);
                xpc_dictionary_set_string(reply, SUInstallServiceErrorLocalizedDescriptionKey, "Unknown install cervice task.");
                xpc_connection_send_message(peer, reply);
                xpc_release(reply);
                
                break;
            }
		}
        [localPool release];
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
