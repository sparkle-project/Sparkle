//
//  SUPlainInstallerInternals.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/9/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "Sparkle.h"
#import "SUPlainInstallerInternals.h"

#import <Security/Security.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <dirent.h>
#import <unistd.h>

@interface SUPlainInstaller (MMExtendedAttributes)
// Removes the directory tree rooted at |root| from the file quarantine.
// The quarantine was introduced on Mac OS X 10.5 and is described at:
//
//   http://developer.apple.com/releasenotes/Carbon/RN-LaunchServices/index.html
//#apple_ref/doc/uid/TP40001369-DontLinkElementID_2
//
// If |root| is not a directory, then it alone is removed from the quarantine.
// Symbolic links, including |root| if it is a symbolic link, will not be
// traversed.
//
// Ordinarily, the quarantine is managed by calling LSSetItemAttribute
// to set the kLSItemQuarantineProperties attribute to a dictionary specifying
// the quarantine properties to be applied.  However, it does not appear to be
// possible to remove an item from the quarantine directly through any public
// Launch Services calls.  Instead, this method takes advantage of the fact
// that the quarantine is implemented in part by setting an extended attribute,
// "com.apple.quarantine", on affected files.  Removing this attribute is
// sufficient to remove files from the quarantine.
+ (void)releaseFromQuarantine:(NSString*)root;
@end

// Authorization code based on generous contribution from Allan Odgaard. Thanks, Allan!

static BOOL AuthorizationExecuteWithPrivilegesAndWait(AuthorizationRef authorization, const char* executablePath, AuthorizationFlags options, const char* const* arguments)
{
	sig_t oldSigChildHandler = signal(SIGCHLD, SIG_DFL);
	BOOL returnValue = YES;

	if (AuthorizationExecuteWithPrivileges(authorization, executablePath, options, (char* const*)arguments, NULL) == errAuthorizationSuccess)
	{
		int status;
		pid_t pid = wait(&status);
		if (pid == -1 || !WIFEXITED(status) || WEXITSTATUS(status) != 0)
			returnValue = NO;
	}
	else
		returnValue = NO;
		
	signal(SIGCHLD, oldSigChildHandler);
	return returnValue;
}

@implementation SUPlainInstaller (Internals)

+ (BOOL)currentUserOwnsPath:(NSString *)oPath
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

+ (NSString *)_temporaryCopyNameForPath:(NSString *)path
{
	// Let's try to read the version number so the filename will be more meaningful.
	NSString *postFix;
	NSBundle *bundle;
	if ((bundle = [NSBundle bundleWithPath:path]))
	{
		// We'll clean it up a little for safety.
		// The cast is necessary because of a bug in the headers in pre-10.5 SDKs
		NSMutableCharacterSet *validCharacters = (id)[NSMutableCharacterSet alphanumericCharacterSet];
		[validCharacters formUnionWithCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@".-()"]];
		postFix = [[bundle objectForInfoDictionaryKey:@"CFBundleVersion"] stringByTrimmingCharactersInSet:[validCharacters invertedSet]];
	}
	else
		postFix = @"old";
	NSString *prefix = [[path stringByDeletingPathExtension] stringByAppendingFormat:@" (%@)", postFix];
	NSString *tempDir = [prefix stringByAppendingPathExtension:[path pathExtension]];
	// Now let's make sure we get a unique path.
	int cnt=2;
	while ([[NSFileManager defaultManager] fileExistsAtPath:tempDir] && cnt <= 999999)
		tempDir = [NSString stringWithFormat:@"%@ %d.%@", prefix, cnt++, [path pathExtension]];
	return tempDir;
}

+ (BOOL)_copyPathWithForcedAuthentication:(NSString *)src toPath:(NSString *)dst error:(NSError **)error
{
	NSString *tmp = [self _temporaryCopyNameForPath:dst];
	const char* srcPath = [src fileSystemRepresentation];
	const char* tmpPath = [tmp fileSystemRepresentation];
	const char* dstPath = [dst fileSystemRepresentation];
	
	struct stat dstSB;
	stat(dstPath, &dstSB);
	
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
			"/bin/rm",
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
			{ "-rf", tmpPath, NULL }, // make room for the temporary file... this is kinda unsafe; should probably do something better.
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
			if (res)
				res = AuthorizationExecuteWithPrivilegesAndWait(auth, executables[commandIndex], kAuthorizationFlagDefaults, argumentLists[commandIndex]);
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
			if (res)
				res = AuthorizationExecuteWithPrivilegesAndWait(auth, executables[commandIndex], kAuthorizationFlagDefaults, argumentLists[commandIndex]);
		}
		
		AuthorizationFree(auth, 0);
		
		if (!res)
		{
			// Something went wrong somewhere along the way, but we're not sure exactly where.
			NSString *errorMessage = [NSString stringWithFormat:@"Authenticated file copy from %@ to %@ failed.", src, dst];
			if (error != NULL)
				*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
		}
	}
	else
	{
		if (error != NULL)
			*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:[NSDictionary dictionaryWithObject:@"Couldn't get permission to authenticate." forKey:NSLocalizedDescriptionKey]];
	}
	return res;
}

+ (BOOL)copyPathWithAuthentication:(NSString *)src overPath:(NSString *)dst error:(NSError **)error
{
	if (![[NSFileManager defaultManager] fileExistsAtPath:dst])
	{
		NSString *errorMessage = [NSString stringWithFormat:@"Couldn't copy %@ over %@ because there is no file at %@.", src, dst, dst];
		if (error != NULL)
			*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUFileCopyFailure userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
		return NO;
	}

	if (![[NSFileManager defaultManager] isWritableFileAtPath:dst] || ![[NSFileManager defaultManager] isWritableFileAtPath:[dst stringByDeletingLastPathComponent]])
		return [self _copyPathWithForcedAuthentication:src toPath:dst error:error];

	NSString *tmpPath = [self _temporaryCopyNameForPath:dst];

	if (![[NSFileManager defaultManager] movePath:dst toPath:tmpPath handler:self])
	{
		if (error != NULL)
			*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUFileCopyFailure userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Couldn't move %@ to %@.", dst, tmpPath] forKey:NSLocalizedDescriptionKey]];
		return NO;			
	}
	if (![[NSFileManager defaultManager] copyPath:src toPath:dst handler:self])
	{
		if (error != NULL)
			*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUFileCopyFailure userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Couldn't copy %@ to %@.", src, dst] forKey:NSLocalizedDescriptionKey]];
		return NO;			
	}
	
	// Trash the old copy of the app.
	NSInteger tag = 0;
	if (![[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:[tmpPath stringByDeletingLastPathComponent] destination:@"" files:[NSArray arrayWithObject:[tmpPath lastPathComponent]] tag:&tag])
		NSLog(@"Sparkle error: couldn't move %@ to the trash. This is often a sign of a permissions error.", tmpPath);
	
	// If the currently-running application is trusted, the new
	// version should be trusted as well.  Remove it from the
	// quarantine to avoid a delay at launch, and to avoid
	// presenting the user with a confusing trust dialog.
	//
	// This needs to be done after the application is moved to its
	// new home in case it's moved across filesystems: if that
	// happens, the move is actually a copy, and it may result
	// in the application being quarantined.
	[self releaseFromQuarantine:dst];
	
	return YES;
}

@end

#include <dlfcn.h>
#include <errno.h>
#include <sys/xattr.h>

@implementation SUPlainInstaller (MMExtendedAttributes)

+ (int)removeXAttr:(const char*)name
          fromFile:(NSString*)file
           options:(int)options
{
	typedef int (*removexattr_type)(const char*, const char*, int);
	// Reference removexattr directly, it's in the SDK.
	static removexattr_type removexattr_func = removexattr;
	
	// Make sure that the symbol is present.  This checks the deployment
	// target instead of the SDK so that it's able to catch dlsym failures
	// as well as the null symbol that would result from building with the
	// 10.4 SDK and a lower deployment target, and running on 10.3.
	if (!removexattr_func) {
		errno = ENOSYS;
		return -1;
	}
	
	const char* path = NULL;
	@try {
		path = [file fileSystemRepresentation];
	}
	@catch (id exception) {
		// -[NSString fileSystemRepresentation] throws an exception if it's
		// unable to convert the string to something suitable.  Map that to
		// EDOM, "argument out of domain", which sort of conveys that there
		// was a conversion failure.
		errno = EDOM;
		return -1;
	}
	
	return removexattr_func(path, name, options);
}

+ (void)releaseFromQuarantine:(NSString*)root
{
	const char* quarantineAttribute = "com.apple.quarantine";
	const int removeXAttrOptions = XATTR_NOFOLLOW;
	
	[self removeXAttr:quarantineAttribute
			 fromFile:root
			  options:removeXAttrOptions];
	
	// Only recurse if it's actually a directory.  Don't recurse into a
	// root-level symbolic link.
	NSDictionary* rootAttributes =
	[[NSFileManager defaultManager] fileAttributesAtPath:root traverseLink:NO];
	NSString* rootType = [rootAttributes objectForKey:NSFileType];
	
	if (rootType == NSFileTypeDirectory) {
		// The NSDirectoryEnumerator will avoid recursing into any contained
		// symbolic links, so no further type checks are needed.
		NSDirectoryEnumerator* directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:root];
		NSString* file = nil;
		while ((file = [directoryEnumerator nextObject])) {
			[self removeXAttr:quarantineAttribute
					 fromFile:[root stringByAppendingPathComponent:file]
					  options:removeXAttrOptions];
		}
	}
}

@end
