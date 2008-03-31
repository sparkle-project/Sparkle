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

#import "NSFileManager+ExtendedAttributes.h"

// TN OV02 says that the range between 1000 and 9999 can be used for
// application-defined errors.  errToolFailedError will indicate that an
// executed program crashed or indicated failure with a nonzero exit status
static const OSStatus errToolFailedError = 1000;

static OSStatus AuthorizationExecuteWithPrivilegesAndWait(
														  AuthorizationRef authorization,
														  const char* executablePath,
														  AuthorizationFlags options,
														  const char* const* arguments) {
	sig_t oldSigChildHandler = signal(SIGCHLD, SIG_DFL);
	OSStatus ret;
	ret = AuthorizationExecuteWithPrivileges(authorization,
	                                         executablePath,
	                                         options,
	                                         (char* const*)arguments,
	                                         NULL);
	if (ret == errAuthorizationSuccess) {
		int status;
		pid_t pid = wait(&status);
		if (pid == -1 ||
		    !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
			ret = errToolFailedError;
		}
	}
	signal(SIGCHLD, oldSigChildHandler);
	return ret;
}

@implementation NSFileManager (SUAuthenticationAdditions)

- (BOOL)currentUserOwnsPath:(NSString *)oPath
{
	const char *path = [oPath fileSystemRepresentation];
	uid_t uid = getuid();
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
					
					size_t len = strlen(path) + 1 + entry->d_namlen + 1;
					char descend[len];
					strlcpy(descend, path, len);
					strlcat(descend, "/", len);
					strlcat(descend, entry->d_name, len);
					NSString* newPath = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:descend length:strlen(descend)];
					res = [self currentUserOwnsPath:newPath];
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
	const char* srcPath = [src fileSystemRepresentation];
	const char* tmpPath = [tmp fileSystemRepresentation];
	const char* dstPath = [dst fileSystemRepresentation];
	
	struct stat sb, dstSB;
	if ((stat(srcPath, &sb) != 0) ||
	    (stat(tmpPath, &sb) == 0) ||
	    (stat(dstPath, &dstSB) != 0)) {
		return NO;
	}
	
	AuthorizationRef auth = NULL;
	OSStatus authStat = errAuthorizationDenied;
	while (authStat == errAuthorizationDenied) {
		authStat = AuthorizationCreate(NULL,
									   kAuthorizationEmptyEnvironment,
									   kAuthorizationFlagDefaults,
									   &auth);
	}
	
	BOOL res = NO;
	if (authStat == errAuthorizationSuccess) {
		res = YES;
		
		char uidgid[42];
		snprintf(uidgid, sizeof(uidgid), "%d:%d",
				 dstSB.st_uid, dstSB.st_gid);
		
		const char* executables[] = {
			"/bin/mv",
			"/bin/mv",
			"/bin/rm",
			NULL,  // pause here and do some housekeeping before
			// continuing
			"/usr/sbin/chown",
			NULL   // stop here for real
		};
		
		// 4 is the maximum number of arguments to any command,
		// including the NULL that signals the end of an argument
		// list.
		const char* const argumentLists[][4] = {
			{ "-f", dstPath, tmpPath, NULL },  // mv
			{ "-f", srcPath, dstPath, NULL },  // mv
			{ "-rf", tmpPath, NULL },  // rm
			{ NULL },  // pause
			{ "-R", uidgid, dstPath, NULL },  // chown
			{ NULL }  // stop
		};
		
		// Process the commands up until the first NULL
		int commandIndex = 0;
		for (; executables[commandIndex] != NULL; ++commandIndex) {
			if (res) {
				res = (
					   AuthorizationExecuteWithPrivilegesAndWait(auth,
																 executables[commandIndex],
																 kAuthorizationFlagDefaults,
																 argumentLists[commandIndex]) ==
					   errAuthorizationSuccess);
			}
		}
		
		// If the currently-running application is trusted, the new
		// version should be trusted as well.  Remove it from the
		// quarantine to avoid a delay at launch, and to avoid
		// presenting the user with a confusing trust dialog.
		//
		// This needs to be done after the application is moved to its
		// new home with "mv" in case it's moved across filesystems: if
		// that happens, "mv" actually performs a copy and may result
		// in the application being quarantined.  It also needs to be
		// done before "chown" changes ownership, because the ownership
		// change will almost certainly make it impossible to change
		// attributes to release the files from the quarantine.
		if (res) {
			[self releaseFromQuarantine:dst];
		}
		
		// Now move past the NULL we found and continue executing
		// commands from the list.
		++commandIndex;
		
		for (; executables[commandIndex] != NULL; ++commandIndex) {
			if (res) {
				res = (
					   AuthorizationExecuteWithPrivilegesAndWait(auth,
																 executables[commandIndex],
																 kAuthorizationFlagDefaults,
																 argumentLists[commandIndex]) ==
					   errAuthorizationSuccess);
			}
		}
		
		AuthorizationFree(auth, 0);
	}
	return res;
}

- (BOOL)copyPath:(NSString *)src overPath:(NSString *)dst withAuthentication:(BOOL)useAuthentication
{
	if ([[NSFileManager defaultManager] isWritableFileAtPath:dst] && [[NSFileManager defaultManager] isWritableFileAtPath:[dst stringByDeletingLastPathComponent]])
	{
		NSInteger tag = 0;
		BOOL result = [[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:[dst stringByDeletingLastPathComponent] destination:@"" files:[NSArray arrayWithObject:[dst lastPathComponent]] tag:&tag];
		result &= [[NSFileManager defaultManager] copyPath:src toPath:dst handler:nil];
		
		// If the currently-running application is trusted, the new
		// version should be trusted as well.  Remove it from the
		// quarantine to avoid a delay at launch, and to avoid
		// presenting the user with a confusing trust dialog.
		//
		// This needs to be done after the application is moved to its
		// new home in case it's moved across filesystems: if that
		// happens, the move is actually a copy, and it may result
		// in the application being quarantined.
		if (result) {
			[self releaseFromQuarantine:dst];
		}
		
		return result;
	}
	else if (useAuthentication == YES)
		return [self _copyPathWithForcedAuthentication:src toPath:dst];
	else
		return NO;
}

-(BOOL)fileManager:(NSFileManager *)manager shouldProceedAfterError:(NSDictionary *)errorInfo
{
	NSLog(@"Sparkle: An error occurred in copying the new version of the product from %@ to %@: %@", [errorInfo objectForKey:@"Path"], [errorInfo objectForKey:@"ToPath"], [errorInfo objectForKey:@"Error"]);
	return NO;
}


@end
