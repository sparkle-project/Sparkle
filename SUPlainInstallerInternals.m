//
//  SUPlainInstallerInternals.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/9/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUUpdater.h"

#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUVersionComparisonProtocol.h"
#import "SUPlainInstallerInternals.h"
#import "SUConstants.h"
#import "SULog.h"

#import <CoreServices/CoreServices.h>
#import <Security/Security.h>
#import <sys/stat.h>
#import <sys/wait.h>
#import <dirent.h>
#import <unistd.h>
#import <sys/param.h>


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
	// *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!

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

+ (NSString *)temporaryNameForPath:(NSString *)path
{
	// Let's try to read the version number so the filename will be more meaningful.
	NSString *postFix;
	NSString *version;
	if ((version = [[NSBundle bundleWithPath:path] objectForInfoDictionaryKey:@"CFBundleVersion"]) && ![version isEqualToString:@""])
	{
		// We'll clean it up a little for safety.
		// The cast is necessary because of a bug in the headers in pre-10.5 SDKs
		NSMutableCharacterSet *validCharacters = (id)[NSMutableCharacterSet alphanumericCharacterSet];
		[validCharacters formUnionWithCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@".-()"]];
		postFix = [version stringByTrimmingCharactersInSet:[validCharacters invertedSet]];
	}
	else
		postFix = @"old";
	NSString *prefix = [[path stringByDeletingPathExtension] stringByAppendingFormat:@" (%@)", postFix];
	NSString *tempDir = [prefix stringByAppendingPathExtension:[path pathExtension]];
	// Now let's make sure we get a unique path.
	unsigned int cnt=2;
	while ([[NSFileManager defaultManager] fileExistsAtPath:tempDir] && cnt <= 999)
		tempDir = [NSString stringWithFormat:@"%@ %u.%@", prefix, cnt++, [path pathExtension]];
	return [tempDir lastPathComponent];
}

+ (NSString *)_temporaryCopyNameForPath:(NSString *)path didFindTrash: (BOOL*)outDidFindTrash
{
	// *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!
	NSString *tempDir = nil;
	
	UInt8			trashPath[MAXPATHLEN +1] = { 0 };
	FSRef			trashRef, pathRef;
	FSVolumeRefNum	vSrcRefNum = kFSInvalidVolumeRefNum;
	FSCatalogInfo	catInfo;
	memset( &catInfo, 0, sizeof(catInfo) );
	OSStatus err = FSPathMakeRef( (UInt8*) [path fileSystemRepresentation], &pathRef, NULL );
	if( err == noErr )
	{
		err = FSGetCatalogInfo( &pathRef, kFSCatInfoVolume, &catInfo, NULL, NULL, NULL );
		vSrcRefNum = catInfo.volume;
	}
	if( err == noErr )
		err = FSFindFolder( vSrcRefNum, kTrashFolderType, kCreateFolder, &trashRef );
	if( err == noErr )
		err = FSGetCatalogInfo( &trashRef, kFSCatInfoVolume, &catInfo, NULL, NULL, NULL );
	if( err == noErr && vSrcRefNum != catInfo.volume )
		err = nsvErr;	// Couldn't find a trash folder on same volume as given path. Docs say this may happen in the future.
	if( err == noErr )
		err = FSRefMakePath( &trashRef, trashPath, MAXPATHLEN );
	if( err == noErr )
		tempDir = [[NSFileManager defaultManager] stringWithFileSystemRepresentation: (char*) trashPath length: strlen((char*) trashPath)];
	if( outDidFindTrash )
		*outDidFindTrash = (tempDir != nil);
	if( !tempDir )
		tempDir = [path stringByDeletingLastPathComponent];
	
	// Let's try to read the version number so the filename will be more meaningful.
	#if TRY_TO_APPEND_VERSION_NUMBER
	NSString *postFix = nil;
	NSString *version = nil;
	if ((version = [[NSBundle bundleWithPath: path] objectForInfoDictionaryKey:@"CFBundleVersion"]) && ![version isEqualToString:@""])
	{
		// We'll clean it up a little for safety.
		// The cast is necessary because of a bug in the headers in pre-10.5 SDKs
		NSMutableCharacterSet *validCharacters = (id)[NSMutableCharacterSet alphanumericCharacterSet];
		[validCharacters formUnionWithCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@".-()"]];
		postFix = [version stringByTrimmingCharactersInSet:[validCharacters invertedSet]];
	}
	else
		postFix = @"old";
	NSString *prefix = [NSString stringWithFormat: @"%@ (%@)", [[path lastPathComponent] stringByDeletingPathExtension], postFix];
	#else
	NSString *prefix = [[path lastPathComponent] stringByDeletingPathExtension];
	#endif
	NSString *tempName = [prefix stringByAppendingPathExtension: [path pathExtension]];
	tempDir = [tempDir stringByAppendingPathComponent: tempName];
	
	// Now let's make sure we get a unique path.
	int cnt=2;
	while ([[NSFileManager defaultManager] fileExistsAtPath:tempDir] && cnt <= 9999)
		tempDir = [[tempDir stringByDeletingLastPathComponent] stringByAppendingPathComponent: [NSString stringWithFormat:@"%@ %d.%@", prefix, cnt++, [path pathExtension]]];
	
	return tempDir;
}

+ (BOOL)_copyPathWithForcedAuthentication:(NSString *)src toPath:(NSString *)dst temporaryPath:(NSString *)tmp error:(NSError **)error
{
	// *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!
	
	const char* srcPath = [src fileSystemRepresentation];
	const char* tmpPath = [tmp fileSystemRepresentation];
	const char* dstPath = [dst fileSystemRepresentation];
	
	struct stat dstSB;
	if( stat(dstPath, &dstSB) != 0 )	// Doesn't exist yet, try containing folder.
	{
		const char*	dstDirPath = [[dst stringByDeletingLastPathComponent] fileSystemRepresentation];
		if( stat(dstDirPath, &dstSB) != 0 )
		{
			NSString *errorMessage = [NSString stringWithFormat:@"Stat on %@ during authenticated file copy failed.", dst];
			if (error != NULL)
				*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUFileCopyFailure userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
			return NO;
		}
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
		snprintf(uidgid, sizeof(uidgid), "%u:%u",
				 dstSB.st_uid, dstSB.st_gid);
		
		// If the currently-running application is trusted, the new
		// version should be trusted as well.  Remove it from the
		// quarantine to avoid a delay at launch, and to avoid
		// presenting the user with a confusing trust dialog.
		//
		// This needs to be done before "chown" changes ownership,
		// because the ownership change will fail if the file is quarantined.
		if (res)
		{
			SULog(@"releaseFromQuarantine");
			[self performSelectorOnMainThread:@selector(releaseFromQuarantine:) withObject:src waitUntilDone:YES];
		}
		
		if( res )	// Set permissions while it's still in source, so we have it with working and correct perms when it arrives at destination.
		{
			const char* coParams[] = { "-R", uidgid, srcPath, NULL };
			res = AuthorizationExecuteWithPrivilegesAndWait( auth, "/usr/sbin/chown", kAuthorizationFlagDefaults, coParams );
			if( !res )
				SULog( @"chown -R %s %s failed.", uidgid, srcPath );
		}
		
		BOOL	haveDst = [[NSFileManager defaultManager] fileExistsAtPath: dst];
		if( res && haveDst )	// If there's something at our tmp path (previous failed update or whatever) delete that first.
		{
			const char*	rmParams[] = { "-rf", tmpPath, NULL };
			res = AuthorizationExecuteWithPrivilegesAndWait( auth, "/bin/rm", kAuthorizationFlagDefaults, rmParams );
			if( !res )
				SULog( @"rm failed" );
		}
		
		if( res && haveDst )	// Move old exe to tmp path.
		{
			const char* mvParams[] = { "-f", dstPath, tmpPath, NULL };
			res = AuthorizationExecuteWithPrivilegesAndWait( auth, "/bin/mv", kAuthorizationFlagDefaults, mvParams );
			if( !res )
				SULog( @"mv 1 failed" );
		}
				
		if( res )	// Move new exe to old exe's path.
		{
			const char* mvParams2[] = { "-f", srcPath, dstPath, NULL };
			res = AuthorizationExecuteWithPrivilegesAndWait( auth, "/bin/mv", kAuthorizationFlagDefaults, mvParams2 );
			if( !res )
				SULog( @"mv 2 failed" );
		}
		
//		if( res && haveDst /*&& !foundTrash*/ )	// If we managed to put the old exe in the trash, leave it there for the user to delete or recover.
//		{									// ...  Otherwise we better delete it, wouldn't want dozens of old versions lying around next to the new one.
//			const char* rmParams2[] = { "-rf", tmpPath, NULL };
//			res = AuthorizationExecuteWithPrivilegesAndWait( auth, "/bin/rm", kAuthorizationFlagDefaults, rmParams2 );
//		}
		
		AuthorizationFree(auth, 0);
		
		// If the currently-running application is trusted, the new
		// version should be trusted as well.  Remove it from the
		// quarantine to avoid a delay at launch, and to avoid
		// presenting the user with a confusing trust dialog.
		//
		// This needs to be done after the application is moved to its
		// new home with "mv" in case it's moved across filesystems: if
		// that happens, "mv" actually performs a copy and may result
		// in the application being quarantined.
        if (res)
		{
			SULog(@"releaseFromQuarantine after installing");
			[self performSelectorOnMainThread:@selector(releaseFromQuarantine:) withObject:dst waitUntilDone:YES];
		}

		if (!res)
		{
			// Something went wrong somewhere along the way, but we're not sure exactly where.
			NSString *errorMessage = [NSString stringWithFormat:@"Authenticated file copy from %@ to %@ failed.", src, dst];
			if (error != nil)
				*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
		}
	}
	else
	{
		if (error != nil)
			*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:[NSDictionary dictionaryWithObject:@"Couldn't get permission to authenticate." forKey:NSLocalizedDescriptionKey]];
	}
	return res;
}

+ (BOOL)_movePathWithForcedAuthentication:(NSString *)src toPath:(NSString *)dst error:(NSError **)error
{
	// *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!
	
	const char* srcPath = [src fileSystemRepresentation];
	const char* dstPath = [dst fileSystemRepresentation];
	const char* dstContainerPath = [[dst stringByDeletingLastPathComponent] fileSystemRepresentation];
	
	struct stat dstSB;
	stat(dstContainerPath, &dstSB);
	
	AuthorizationRef auth = NULL;
	OSStatus authStat = errAuthorizationDenied;
	while( authStat == errAuthorizationDenied )
	{
		authStat = AuthorizationCreate(NULL,
									   kAuthorizationEmptyEnvironment,
									   kAuthorizationFlagDefaults,
									   &auth);
	}
	
	BOOL res = NO;
	if (authStat == errAuthorizationSuccess)
	{
		res = YES;
		
		char uidgid[42];
		snprintf(uidgid, sizeof(uidgid), "%d:%d",
				 dstSB.st_uid, dstSB.st_gid);
		
		if( res )	// Set permissions while it's still in source, so we have it with working and correct perms when it arrives at destination.
		{
			const char* coParams[] = { "-R", uidgid, srcPath, NULL };
			res = AuthorizationExecuteWithPrivilegesAndWait( auth, "/usr/sbin/chown", kAuthorizationFlagDefaults, coParams );
			if( !res )
				SULog(@"Can't set permissions");
		}
		
		BOOL	haveDst = [[NSFileManager defaultManager] fileExistsAtPath: dst];
		if( res && haveDst )	// If there's something at our tmp path (previous failed update or whatever) delete that first.
		{
			const char*	rmParams[] = { "-rf", dstPath, NULL };
			res = AuthorizationExecuteWithPrivilegesAndWait( auth, "/bin/rm", kAuthorizationFlagDefaults, rmParams );
			if( !res )
				SULog(@"Can't remove destination file");
		}
		
		if( res )	// Move!.
		{
			const char* mvParams[] = { "-f", srcPath, dstPath, NULL };
			res = AuthorizationExecuteWithPrivilegesAndWait( auth, "/bin/mv", kAuthorizationFlagDefaults, mvParams );
			if( !res )
				SULog(@"Can't move source file");
		}
		
		AuthorizationFree(auth, 0);
		
		if (!res)
		{
			// Something went wrong somewhere along the way, but we're not sure exactly where.
			NSString *errorMessage = [NSString stringWithFormat:@"Authenticated file move from %@ to %@ failed.", src, dst];
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


+ (BOOL)_removeFileAtPathWithForcedAuthentication:(NSString *)src error:(NSError **)error
{
	// *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!
	
	const char* srcPath = [src fileSystemRepresentation];
	
	AuthorizationRef auth = NULL;
	OSStatus authStat = errAuthorizationDenied;
	while( authStat == errAuthorizationDenied )
	{
		authStat = AuthorizationCreate(NULL,
									   kAuthorizationEmptyEnvironment,
									   kAuthorizationFlagDefaults,
									   &auth);
	}
	
	BOOL res = NO;
	if (authStat == errAuthorizationSuccess)
	{
		res = YES;
		
		if( res )	// If there's something at our tmp path (previous failed update or whatever) delete that first.
		{
			const char*	rmParams[] = { "-rf", srcPath, NULL };
			res = AuthorizationExecuteWithPrivilegesAndWait( auth, "/bin/rm", kAuthorizationFlagDefaults, rmParams );
			if( !res )
				SULog(@"Can't remove destination file");
		}
		
		AuthorizationFree(auth, 0);
		
		if (!res)
		{
			// Something went wrong somewhere along the way, but we're not sure exactly where.
			NSString *errorMessage = [NSString stringWithFormat:@"Authenticated file remove from %@ failed.", src];
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

+ (BOOL)_removeFileAtPath:(NSString *)path error: (NSError**)error
{
	BOOL	success = YES;
#if MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4
    if( ![[NSFileManager defaultManager] removeFileAtPath: path handler: nil] )
#else
	if( ![[NSFileManager defaultManager] removeItemAtPath: path error: NULL] )
#endif
	{
		success = [self _removeFileAtPathWithForcedAuthentication: path error: error];
	}
	
	return success;
}

+ (void)_movePathToTrash:(NSString *)path
{
	//SULog(@"Moving %@ to the trash.", path);
	NSInteger tag = 0;
	if (![[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:[path stringByDeletingLastPathComponent] destination:@"" files:[NSArray arrayWithObject:[path lastPathComponent]] tag:&tag])
	{
		BOOL		didFindTrash = NO;
		NSString*	trashPath = [self _temporaryCopyNameForPath: path didFindTrash: &didFindTrash];
		if( didFindTrash )
		{
			NSError		*err = nil;
			if( ![self _movePathWithForcedAuthentication: path toPath: trashPath error: &err] )
				SULog(@"Sparkle error: couldn't move %@ to the trash (%@). %@", path, trashPath, err);
		}
		else
			SULog(@"Sparkle error: couldn't move %@ to the trash. This is often a sign of a permissions error.", path);
	}
	else
		;//SULog(@"Moved %@ to the trash.", path);
}

+ (BOOL)copyPathWithAuthentication:(NSString *)src overPath:(NSString *)dst temporaryName:(NSString *)tmp error:(NSError **)error
{
	FSRef		srcRef, dstRef, dstDirRef, movedRef, tmpDirRef;
	OSStatus	err;
	BOOL		hadFileAtDest = NO, didFindTrash = NO;
	NSString	*tmpPath = [self _temporaryCopyNameForPath: dst didFindTrash: &didFindTrash];
	
	// Make FSRef for destination:
	err = FSPathMakeRefWithOptions((UInt8 *)[dst fileSystemRepresentation], kFSPathMakeRefDoNotFollowLeafSymlink, &dstRef, NULL);
	hadFileAtDest = (err == noErr);	// There is a file at the destination, move it aside. If we normalized the name, we might not get here, so don't error.
	if( hadFileAtDest )
	{
		if (0 != access([dst fileSystemRepresentation], W_OK) || 0 != access([[dst stringByDeletingLastPathComponent] fileSystemRepresentation], W_OK))
		{
			return [self _copyPathWithForcedAuthentication:src toPath:dst temporaryPath:tmpPath error:error];
		}
	}
	else
	{
		if (0 != access([[dst stringByDeletingLastPathComponent] fileSystemRepresentation], W_OK)
			|| 0 != access([[[dst stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] fileSystemRepresentation], W_OK))
		{
			return [self _copyPathWithForcedAuthentication:src toPath:dst temporaryPath:tmpPath error:error];
		}
	}
	
	if( hadFileAtDest )
	{
		err = FSPathMakeRef((UInt8 *)[[tmpPath stringByDeletingLastPathComponent] fileSystemRepresentation], &tmpDirRef, NULL);
		if (err != noErr)
			err = FSPathMakeRef((UInt8 *)[[dst stringByDeletingLastPathComponent] fileSystemRepresentation], &tmpDirRef, NULL);
	}
	
	err = FSPathMakeRef((UInt8 *)[[dst stringByDeletingLastPathComponent] fileSystemRepresentation], &dstDirRef, NULL);
	
	if (err == noErr && hadFileAtDest)
	{ 
		if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_5)
		{
			NSFileManager *manager = [[[NSFileManager alloc] init] autorelease];
			BOOL success = [manager moveItemAtPath:dst toPath:tmpPath error:error];
			if (!success && hadFileAtDest)
			{
				if (error != NULL)
					*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUFileCopyFailure userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Couldn't move %@ to %@.", dst, tmpPath] forKey:NSLocalizedDescriptionKey]];
				return NO;
			}
			
		} else {
			err = FSMoveObjectSync(&dstRef, &tmpDirRef, (CFStringRef)[tmpPath lastPathComponent], &movedRef, 0);
			if (err != noErr && hadFileAtDest)
			{
				if (error != NULL)
					*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUFileCopyFailure userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Couldn't move %@ to %@.", dst, tmpPath] forKey:NSLocalizedDescriptionKey]];
				return NO;			
			}
		}
	}
	
	err = FSPathMakeRef((UInt8 *)[src fileSystemRepresentation], &srcRef, NULL);
	if (err == noErr)
	{
		if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_5)
		{
			NSFileManager *manager = [[[NSFileManager alloc] init] autorelease];
			BOOL success = [manager copyItemAtPath:src toPath:dst error:error];
			if (!success)
			{
				// We better move the old version back to its old location
				if( hadFileAtDest )
					success = [manager moveItemAtPath:tmpPath toPath:dst error:error];
				if (error != NULL)
					*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUFileCopyFailure userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Couldn't move %@ to %@.", dst, tmpPath] forKey:NSLocalizedDescriptionKey]];
				return NO;

			}
		} else {
			err = FSCopyObjectSync(&srcRef, &dstDirRef, (CFStringRef)[dst lastPathComponent], NULL, 0);
			if (err != noErr)
			{
				// We better move the old version back to its old location
				if( hadFileAtDest )
					FSMoveObjectSync(&movedRef, &dstDirRef, (CFStringRef)[dst lastPathComponent], &movedRef, 0);
				if (error != NULL)
					*error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUFileCopyFailure userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:@"Couldn't copy %@ to %@.", src, dst] forKey:NSLocalizedDescriptionKey]];
				return NO;			
			}
		}
	}
		
	// If the currently-running application is trusted, the new
	// version should be trusted as well.  Remove it from the
	// quarantine to avoid a delay at launch, and to avoid
	// presenting the user with a confusing trust dialog.
	//
	// This needs to be done after the application is moved to its
	// new home in case it's moved across filesystems: if that
	// happens, the move is actually a copy, and it may result
	// in the application being quarantined.
	if ([NSThread isMultiThreaded])
		[self performSelectorOnMainThread:@selector(releaseFromQuarantine:) withObject:dst waitUntilDone:YES];
	else
		[self releaseFromQuarantine:dst];
	
	return YES;
}

@end

#import <dlfcn.h>
#import <errno.h>
#import <sys/xattr.h>

@implementation SUPlainInstaller (MMExtendedAttributes)

+ (int)removeXAttr:(const char*)name
          fromFile:(NSString*)file
           options:(int)options
{
	// *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!

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
	// *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!

	const char* quarantineAttribute = "com.apple.quarantine";
	const int removeXAttrOptions = XATTR_NOFOLLOW;
	
	[self removeXAttr:quarantineAttribute
			 fromFile:root
			  options:removeXAttrOptions];
	
	// Only recurse if it's actually a directory.  Don't recurse into a
	// root-level symbolic link.
#if MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4
	NSDictionary* rootAttributes = [[NSFileManager defaultManager] fileAttributesAtPath:root traverseLink:NO];
#else
	NSDictionary* rootAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:root error:nil];
#endif
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
