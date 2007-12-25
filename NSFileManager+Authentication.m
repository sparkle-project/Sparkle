//
//  NSFileManager+Authentication.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/9/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

// This code based on generous contribution from Allan Odgaard. Thanks, Allan!

#import "Sparkle.h"
#import "NSFileManager+Authentication.h"

#import <Security/Security.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <dirent.h>
#import <unistd.h>

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

- (BOOL)_copyPathWithForcedAuthentication:(NSString *)src toPath:(NSString *)dst
{
	NSString *tmp = [[[dst stringByDeletingPathExtension] stringByAppendingString:@".old"] stringByAppendingPathExtension:[dst pathExtension]];
	BOOL res = NO;
	struct stat sb;
	if((stat([src UTF8String], &sb) != 0) || (stat([tmp UTF8String], &sb) == 0) || stat([dst UTF8String], &sb) != 0)
		return false;
	
	NSString *command = [NSString stringWithFormat:@"mv -f \"%@\" \"%@\" && cp -f -R \"%@\" \"%@\" && rm -rf \"%@\" && chown -R %d:%d \"%@\"",
						 dst,
						 tmp,
						 src,
						 dst,
						 tmp,
						 sb.st_uid,
						 sb.st_gid,
						 dst];
	
	AuthorizationRef auth;
	if(AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &auth) == errAuthorizationSuccess)
	{
		char const* arguments[] = { "-c", [command UTF8String], NULL };
		if(AuthorizationExecuteWithPrivileges(auth, "/bin/sh", kAuthorizationFlagDefaults, (char**)arguments, NULL) == errAuthorizationSuccess)
		{
			int status;
			int pid = wait(&status);
			if(pid != -1 && WIFEXITED(status) && WEXITSTATUS(status) == 0)
				res = YES;
		}
	}
	AuthorizationFree(auth, 0);
	
	return res;	
}

- (BOOL)copyPath:(NSString *)src overPath:(NSString *)dst withAuthentication:(BOOL)useAuthentication
{
	if ([[NSFileManager defaultManager] isWritableFileAtPath:dst] && [[NSFileManager defaultManager] isWritableFileAtPath:[dst stringByDeletingLastPathComponent]])
	{
		NSInteger tag = 0;
		BOOL result = [[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:[dst stringByDeletingLastPathComponent] destination:@"" files:[NSArray arrayWithObject:[dst lastPathComponent]] tag:&tag];
		result &= [[NSFileManager defaultManager] copyPath:src toPath:dst handler:nil];
		return result;
	}
	else if (useAuthentication == YES)
		return [self _copyPathWithForcedAuthentication:src toPath:dst];
	else
		return NO;
}

@end
