//
//  SUUpdater+Authentication.m
//  Pixen
//
//  Created by Andy Matuschak on 3/9/06.
//  Copyright 2006 __MyCompanyName__. All rights reserved.
//

#import "SUUpdater.h"
#import "sys/stat.h"
#import <Security/Security.h>

@implementation SUUpdater (SUAuthenticationAdditions)

// Thanks to Allan Odgaard for this!
- (BOOL)moveFileWithAuthenticationFrom:(NSString *)src toNewPath:(NSString *)dst withTempPath:(NSString *)tmp
{
	BOOL res = NO;
	struct stat sb;
	if((stat([src UTF8String], &sb) != 0) || (stat([tmp UTF8String], &sb) == 0) || stat([dst UTF8String], &sb) != 0)
		return false;
	
	char* buf = NULL;
	asprintf(&buf,
			 "mv -f \"$DST_PATH\" \"$TMP_PATH\" && "
			 "mv -f \"$SRC_PATH\" \"$DST_PATH\" && "
			 "rm -rf \"$TMP_PATH\" && "
			 "chown -R %d:%d \"$DST_PATH\"",
			 sb.st_uid, sb.st_gid);
	
	if(!buf)
		return false;
	
	AuthorizationRef auth;
	if(AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &auth) == errAuthorizationSuccess)
	{
		setenv("SRC_PATH", [src UTF8String], 1);
		setenv("DST_PATH", [dst UTF8String], 1);
		setenv("TMP_PATH", [tmp UTF8String], 1);
		
		char const* arguments[] = { "-c", buf, NULL };
		if(AuthorizationExecuteWithPrivileges(auth, "/bin/sh", kAuthorizationFlagDefaults, (char**)arguments, NULL) == errAuthorizationSuccess)
		{
			int status;
			int pid = wait(&status);
			if(pid != -1 && WIFEXITED(status) && WEXITSTATUS(status) == 0)
				res = YES;
		}
	}
	free(buf);
	return res;
}

@end
