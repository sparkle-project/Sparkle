//
//  NSFileManager+Authentication.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/9/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

// This code based on generous contribution from Allan Odgaard. Thanks, Allan!

#import "sys/stat.h"
#import <Security/Security.h>

#import <unistd.h>
#import <sys/stat.h>
#import <dirent.h>

@implementation NSFileManager (SUAuthenticationAdditions)

- (BOOL)currentUserOwnsPath:(NSString *)oPath
{
	char *path = (char *)[oPath fileSystemRepresentation];
	unsigned int uid = getuid();
	bool res = false;
	struct stat sb;
	if(stat(path, &sb) == 0)
	{
		if(sb.st_uid == uid)
		{
			res = true;
			if(sb.st_mode & S_IFDIR)
			{
				DIR* dir = opendir(path);
				struct dirent* entry = NULL;
				while(res && (entry = readdir(dir)))
				{
					if(strcmp(entry->d_name, ".") == 0 || strcmp(entry->d_name, "..") == 0)
						continue;
					
					char descend[strlen(path) + 1 + entry->d_namlen + 1];
					strcpy(descend, path);
					strcat(descend, "/");
					strcat(descend, entry->d_name);
					res = [self currentUserOwnsPath:[NSString stringWithUTF8String:descend]];
				}
				closedir(dir);
			}
		}
	}
	return res;
}

- (BOOL)_movePathWithForcedAuthentication:(NSString *)src toPath:(NSString *)dst
{
	NSString *tmp = [[[dst stringByDeletingPathExtension] stringByAppendingString:@".old"] stringByAppendingPathExtension:[dst pathExtension]];
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
		sig_t oldSigChildHandler = signal(SIGCHLD, SIG_DFL);
		char const* arguments[] = { "-c", buf, NULL };
		if(AuthorizationExecuteWithPrivileges(auth, "/bin/sh", kAuthorizationFlagDefaults, (char**)arguments, NULL) == errAuthorizationSuccess)
		{
			int status;
			int pid = wait(&status);
			if(pid != -1 && WIFEXITED(status) && WEXITSTATUS(status) == 0)
				res = YES;
		}
		signal(SIGCHLD, oldSigChildHandler);
	}
	AuthorizationFree(auth, 0);
	free(buf);
	return res;	
}

- (BOOL)movePathWithAuthentication:(NSString *)src toPath:(NSString *)dst
{
	if ([[NSFileManager defaultManager] isWritableFileAtPath:dst] && [[NSFileManager defaultManager] isWritableFileAtPath:[dst stringByDeletingLastPathComponent]])
	{
		int tag = 0;
		BOOL result = [[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:[dst stringByDeletingLastPathComponent] destination:@"" files:[NSArray arrayWithObject:[dst lastPathComponent]] tag:&tag];
		result &= [[NSFileManager defaultManager] movePath:src toPath:dst handler:NULL];
		return result;
	}
	else
	{
		return [self _movePathWithForcedAuthentication:src toPath:dst];
	}
}

@end
