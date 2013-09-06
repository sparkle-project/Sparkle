//
//  SUXPC.m
//  Sparkle
//
//  Created by Whitney Young on 3/19/12.
//  Copyright (c) 2012 FadingRed. All rights reserved.
//

#import <xpc/xpc.h>
#import "SUXPC.h"


@implementation SUXPC

+ (BOOL)copyPathWithAuthentication:(NSString *)src overPath:(NSString *)dst temporaryName:(NSString *)tmp error:(NSError **)error {
	xpc_connection_t connection = xpc_connection_create("com.andymatuschak.Sparkle.SandboxService", NULL);
	xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
		xpc_dictionary_apply(event, ^bool(const char *key, xpc_object_t value) {
			NSLog(@"XPC %s: %s", key, xpc_string_get_string_ptr(value));
			return true;
		});
	});
	xpc_connection_resume(connection);

	xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_string(message, "id", "copy_path");
	
	if( src )
		xpc_dictionary_set_string(message, "source", [src fileSystemRepresentation]);
	if( dst )
		xpc_dictionary_set_string(message, "destination", [dst fileSystemRepresentation]);
	if( tmp )
		xpc_dictionary_set_string(message, "tmp", [tmp UTF8String]);
	
	xpc_object_t response = xpc_connection_send_message_with_reply_sync(connection, message);
	xpc_type_t type = xpc_get_type(response);
	return type == XPC_TYPE_DICTIONARY;
}

+ (void)launchTaskWithLaunchPath:(NSString *)path arguments:(NSArray *)arguments {
	xpc_connection_t connection = xpc_connection_create("com.andymatuschak.Sparkle.SandboxService", NULL);
	xpc_connection_set_event_handler(connection, ^(xpc_object_t event) {
		xpc_dictionary_apply(event, ^bool(const char *key, xpc_object_t value) {
			NSLog(@"XPC %s: %s", key, xpc_string_get_string_ptr(value));
			return true;
		});
	});
	xpc_connection_resume(connection);
	
	xpc_object_t message = xpc_dictionary_create(NULL, NULL, 0);
	xpc_dictionary_set_string(message, "id", "launch_task");
	
	if( path )
		xpc_dictionary_set_string(message, "path", [path fileSystemRepresentation]);
	
	xpc_object_t array = xpc_array_create(NULL, 0);
	for (id argument in arguments) {
		xpc_array_append_value(array, xpc_string_create([argument UTF8String]));
	}
	
	xpc_dictionary_set_value(message, "arguments", array);
	
	xpc_object_t response = xpc_connection_send_message_with_reply_sync(connection, message);
	xpc_type_t type = xpc_get_type(response);
	BOOL success = (type == XPC_TYPE_DICTIONARY);
	
	if (!success) {
		NSLog(@"XPC launch error");
	}
}

@end
