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

#include <CoreServices/CoreServices.h>
#include <Security/Security.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <dirent.h>
#include <unistd.h>
#include <sys/param.h>

#if __MAC_OS_X_VERSION_MAX_ALLOWED < 101000
extern NSString *const NSURLQuarantinePropertiesKey WEAK_IMPORT_ATTRIBUTE;
#endif

static inline void PerformOnMainThreadSync(dispatch_block_t theBlock)
{
    if ([NSThread isMainThread]) {
        theBlock();
    } else {
        dispatch_sync(dispatch_get_main_queue(), theBlock);
    }
}

@interface SUPlainInstaller (MMExtendedAttributes)
// Removes the directory tree rooted at |root| from the file quarantine.
// The quarantine was introduced on OS X 10.5 and is described at:
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
+ (void)releaseFromQuarantine:(NSString *)root;
@end

// Authorization code based on generous contribution from Allan Odgaard. Thanks, Allan!
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations" // this is terrible; will fix later probably
static BOOL AuthorizationExecuteWithPrivilegesAndWait(AuthorizationRef authorization, const char *executablePath, AuthorizationFlags options, char *const *arguments)
{
    // *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!

    sig_t oldSigChildHandler = signal(SIGCHLD, SIG_DFL);
    BOOL returnValue = YES;

	if (AuthorizationExecuteWithPrivileges(authorization, executablePath, options, arguments, NULL) == errAuthorizationSuccess)
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
#pragma clang diagnostic pop

@implementation SUPlainInstaller (Internals)

+ (NSString *)temporaryNameForPath:(NSString *)path
{
    // Let's try to read the version number so the filename will be more meaningful.
    NSString *postFix;
    NSString *version;
	if ((version = [[NSBundle bundleWithPath:path] objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey]) && ![version isEqualToString:@""])
	{
        NSMutableCharacterSet *validCharacters = [NSMutableCharacterSet alphanumericCharacterSet];
        [validCharacters formUnionWithCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@".-()"]];
        postFix = [version stringByTrimmingCharactersInSet:[validCharacters invertedSet]];
	}
	else
        postFix = @"old";
    NSString *prefix = [[path stringByDeletingPathExtension] stringByAppendingFormat:@" (%@)", postFix];
    NSString *tempDir = [prefix stringByAppendingPathExtension:[path pathExtension]];
    // Now let's make sure we get a unique path.
    unsigned int cnt = 2;
    while ([[NSFileManager defaultManager] fileExistsAtPath:tempDir] && cnt <= 999)
        tempDir = [NSString stringWithFormat:@"%@ %u.%@", prefix, cnt++, [path pathExtension]];
    return [tempDir lastPathComponent];
}

+ (NSString *)_temporaryCopyNameForPath:(NSString *)path didFindTrash:(BOOL *)outDidFindTrash
{
    // *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!
    NSString *tempDir = nil;

    UInt8 trashPath[MAXPATHLEN + 1] = { 0 };
    FSRef trashRef, pathRef;
    FSVolumeRefNum vSrcRefNum = kFSInvalidVolumeRefNum;
    FSCatalogInfo catInfo;
    memset(&catInfo, 0, sizeof(catInfo));
    OSStatus err = FSPathMakeRef((const UInt8 *)[path fileSystemRepresentation], &pathRef, NULL);
	if( err == noErr )
	{
        err = FSGetCatalogInfo(&pathRef, kFSCatInfoVolume, &catInfo, NULL, NULL, NULL);
        vSrcRefNum = catInfo.volume;
    }
    if (err == noErr)
        err = FSFindFolder(vSrcRefNum, kTrashFolderType, kCreateFolder, &trashRef);
    if (err == noErr)
        err = FSGetCatalogInfo(&trashRef, kFSCatInfoVolume, &catInfo, NULL, NULL, NULL);
    if (err == noErr && vSrcRefNum != catInfo.volume)
        err = nsvErr; // Couldn't find a trash folder on same volume as given path. Docs say this may happen in the future.
    if (err == noErr)
        err = FSRefMakePath(&trashRef, trashPath, MAXPATHLEN);
    if (err == noErr)
        tempDir = [[NSFileManager defaultManager] stringWithFileSystemRepresentation:(char *)trashPath length:strlen((char *)trashPath)];
    if (outDidFindTrash)
        *outDidFindTrash = (tempDir != nil);
    if (!tempDir)
        tempDir = [path stringByDeletingLastPathComponent];

    // Let's try to read the version number so the filename will be more meaningful
    NSString *prefix;
    if ([[[NSBundle bundleWithIdentifier:SUBundleIdentifier] infoDictionary][SUAppendVersionNumberKey] boolValue]) {
        NSString *postFix = nil;
        NSString *version = nil;
        if ((version = [[NSBundle bundleWithPath: path] objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey]) && ![version isEqualToString:@""])
        {
            NSMutableCharacterSet *validCharacters = [NSMutableCharacterSet alphanumericCharacterSet];
            [validCharacters formUnionWithCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@".-()"]];
            postFix = [version stringByTrimmingCharactersInSet:[validCharacters invertedSet]];
        }
        else {
            postFix = @"old";
        }
        prefix = [NSString stringWithFormat:@"%@ (%@)", [[path lastPathComponent] stringByDeletingPathExtension], postFix];
    } else {
        prefix = [[path lastPathComponent] stringByDeletingPathExtension];
    }
    NSString *tempName = [prefix stringByAppendingPathExtension:[path pathExtension]];
    tempDir = [tempDir stringByAppendingPathComponent:tempName];

    // Now let's make sure we get a unique path.
    int cnt = 2;
    while ([[NSFileManager defaultManager] fileExistsAtPath:tempDir] && cnt <= 9999) {
        tempDir = [[tempDir stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@ %d.%@", prefix, cnt++, [path pathExtension]]];
    }

    return tempDir;
}

+ (BOOL)_copyPathWithForcedAuthentication:(NSString *)src toPath:(NSString *)dst temporaryPath:(NSString *)tmp error:(NSError *__autoreleasing *)error
{
    // *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!

    char srcPath[PATH_MAX] = {0};
    [src getFileSystemRepresentation:srcPath maxLength:sizeof(srcPath)];

    char tmpPath[PATH_MAX] = {0};
    [tmp getFileSystemRepresentation:tmpPath maxLength:sizeof(tmpPath)];

    char dstPath[PATH_MAX] = {0};
    [dst getFileSystemRepresentation:dstPath maxLength:sizeof(dstPath)];

    struct stat dstSB;
    if (stat(dstPath, &dstSB) != 0) // Doesn't exist yet, try containing folder.
    {
        const char *dstDirPath = [[dst stringByDeletingLastPathComponent] fileSystemRepresentation];
		if( stat(dstDirPath, &dstSB) != 0 )
		{
            NSString *errorMessage = [NSString stringWithFormat:@"Stat on %@ during authenticated file copy failed.", dst];
            if (error != NULL)
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUFileCopyFailure userInfo:@{ NSLocalizedDescriptionKey: errorMessage }];
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
        // This needs to be done after the application is moved to its
        // new home with "mv" in case it's moved across filesystems: if
        // that happens, "mv" actually performs a copy and may result
        // in the application being quarantined.  It also needs to be
        // done before "chown" changes ownership, because the ownership
        // change will almost certainly make it impossible to change
        // attributes to release the files from the quarantine.
		if (res)
		{
            SULog(@"releaseFromQuarantine");
            PerformOnMainThreadSync(^{
				[self releaseFromQuarantine:src];
            });
        }

        if (res) // Set permissions while it's still in source, so we have it with working and correct perms when it arrives at destination.
        {
            char *coParams[] = { "-R", uidgid, srcPath, NULL };
            res = AuthorizationExecuteWithPrivilegesAndWait(auth, "/usr/sbin/chown", kAuthorizationFlagDefaults, coParams);
            if (!res)
                SULog(@"chown -R %@ %@ failed.", @(uidgid), @(srcPath));
        }

        BOOL haveDst = [[NSFileManager defaultManager] fileExistsAtPath:dst];
        if (res && haveDst) // If there's something at our tmp path (previous failed update or whatever) delete that first.
        {
            char *rmParams[] = { "-rf", tmpPath, NULL };
            res = AuthorizationExecuteWithPrivilegesAndWait(auth, "/bin/rm", kAuthorizationFlagDefaults, rmParams);
            if (!res)
                SULog(@"rm failed");
        }

        if (res && haveDst) // Move old exe to tmp path.
        {
            char *mvParams[] = { "-f", dstPath, tmpPath, NULL };
            res = AuthorizationExecuteWithPrivilegesAndWait(auth, "/bin/mv", kAuthorizationFlagDefaults, mvParams);
            if (!res)
                SULog(@"mv 1 failed");
        }

        if (res) // Move new exe to old exe's path.
        {
            char *mvParams2[] = { "-f", srcPath, dstPath, NULL };
            res = AuthorizationExecuteWithPrivilegesAndWait(auth, "/bin/mv", kAuthorizationFlagDefaults, mvParams2);
            if (!res)
                SULog(@"mv 2 failed");
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
            PerformOnMainThreadSync(^{
				[self releaseFromQuarantine:dst];
            });
        }

		if (!res)
		{
            // Something went wrong somewhere along the way, but we're not sure exactly where.
            NSString *errorMessage = [NSString stringWithFormat:@"Authenticated file copy from %@ to %@ failed.", src, dst];
            if (error != nil)
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:@{ NSLocalizedDescriptionKey: errorMessage }];
        }
	}
	else
	{
        if (error != nil)
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:@{ NSLocalizedDescriptionKey: @"Couldn't get permission to authenticate." }];
    }
    return res;
}

+ (BOOL)_movePathWithForcedAuthentication:(NSString *)src toPath:(NSString *)dst error:(NSError *__autoreleasing *)error
{
    // *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!

    char srcPath[PATH_MAX] = {0};
    [src getFileSystemRepresentation:srcPath maxLength:sizeof(srcPath)];

    char dstPath[PATH_MAX] = {0};
    [dst getFileSystemRepresentation:dstPath maxLength:sizeof(dstPath)];

    char dstContainerPath[PATH_MAX] = {0};
    [dst.stringByDeletingLastPathComponent getFileSystemRepresentation:dstContainerPath maxLength:sizeof(dstContainerPath)];

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

        if (res) // Set permissions while it's still in source, so we have it with working and correct perms when it arrives at destination.
        {
            char *coParams[] = { "-R", uidgid, srcPath, NULL };
            res = AuthorizationExecuteWithPrivilegesAndWait(auth, "/usr/sbin/chown", kAuthorizationFlagDefaults, coParams);
            if (!res)
                SULog(@"Can't set permissions");
        }

        BOOL haveDst = [[NSFileManager defaultManager] fileExistsAtPath:dst];
        if (res && haveDst) // If there's something at our tmp path (previous failed update or whatever) delete that first.
        {
            char *rmParams[] = { "-rf", dstPath, NULL };
            res = AuthorizationExecuteWithPrivilegesAndWait(auth, "/bin/rm", kAuthorizationFlagDefaults, rmParams);
            if (!res)
                SULog(@"Can't remove destination file");
        }

        if (res) // Move!.
        {
            char *mvParams[] = { "-f", srcPath, dstPath, NULL };
            res = AuthorizationExecuteWithPrivilegesAndWait(auth, "/bin/mv", kAuthorizationFlagDefaults, mvParams);
            if (!res)
                SULog(@"Can't move source file");
        }

        AuthorizationFree(auth, 0);

		if (!res)
		{
            // Something went wrong somewhere along the way, but we're not sure exactly where.
            NSString *errorMessage = [NSString stringWithFormat:@"Authenticated file move from %@ to %@ failed.", src, dst];
            if (error != NULL)
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:@{ NSLocalizedDescriptionKey: errorMessage }];
        }
	}
	else
	{
        if (error != NULL)
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:@{ NSLocalizedDescriptionKey: @"Couldn't get permission to authenticate." }];
    }
    return res;
}


+ (BOOL)_removeFileAtPathWithForcedAuthentication:(NSString *)src error:(NSError *__autoreleasing *)error
{
    // *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!

    char srcPath[PATH_MAX] = {0};
    [src getFileSystemRepresentation:srcPath maxLength:sizeof(srcPath)];

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

        if (res) // If there's something at our tmp path (previous failed update or whatever) delete that first.
        {
            char *rmParams[] = { "-rf", srcPath, NULL };
            res = AuthorizationExecuteWithPrivilegesAndWait(auth, "/bin/rm", kAuthorizationFlagDefaults, rmParams);
            if (!res)
                SULog(@"Can't remove destination file");
        }

        AuthorizationFree(auth, 0);

		if (!res)
		{
            // Something went wrong somewhere along the way, but we're not sure exactly where.
            NSString *errorMessage = [NSString stringWithFormat:@"Authenticated file remove from %@ failed.", src];
            if (error != NULL)
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:@{ NSLocalizedDescriptionKey: errorMessage }];
        }
	}
	else
	{
        if (error != NULL)
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:@{ NSLocalizedDescriptionKey: @"Couldn't get permission to authenticate." }];
    }
    return res;
}

+ (BOOL)_removeFileAtPath:(NSString *)path error:(NSError *__autoreleasing *)error
{
    BOOL success = YES;
	if( ![[NSFileManager defaultManager] removeItemAtPath: path error: NULL] )
	{
        success = [self _removeFileAtPathWithForcedAuthentication:path error:error];
    }

    return success;
}

+ (void)_movePathToTrash:(NSString *)path
{
    //SULog(@"Moving %@ to the trash.", path);
    NSInteger tag = 0;
	if (![[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:[path stringByDeletingLastPathComponent] destination:@"" files:@[[path lastPathComponent]] tag:&tag])
	{
        BOOL didFindTrash = NO;
        NSString *trashPath = [self _temporaryCopyNameForPath:path didFindTrash:&didFindTrash];
		if( didFindTrash )
		{
            NSError *err = nil;
            if (![self _movePathWithForcedAuthentication:path toPath:trashPath error:&err]) {
                SULog(@"Error: couldn't move %@ to the trash (%@). %@", path, trashPath, err);
            }
		}
        else {
            SULog(@"Error: couldn't move %@ to the trash. This is often a sign of a permissions error.", path);
        }
	}
}

+ (BOOL)copyPathWithAuthentication:(NSString *)src overPath:(NSString *)dst temporaryName:(NSString *)__unused tmp error:(NSError *__autoreleasing *)error
{
    FSRef srcRef, dstRef, dstDirRef, tmpDirRef;
    OSStatus err;
    BOOL hadFileAtDest = NO, didFindTrash = NO;
    NSString *tmpPath = [self _temporaryCopyNameForPath:dst didFindTrash:&didFindTrash];

    // Make FSRef for destination:
    err = FSPathMakeRefWithOptions((const UInt8 *)[dst fileSystemRepresentation], kFSPathMakeRefDoNotFollowLeafSymlink, &dstRef, NULL);
    hadFileAtDest = (err == noErr); // There is a file at the destination, move it aside. If we normalized the name, we might not get here, so don't error.
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
        err = FSPathMakeRef((const UInt8 *)[[tmpPath stringByDeletingLastPathComponent] fileSystemRepresentation], &tmpDirRef, NULL);
        if (err != noErr)
            FSPathMakeRef((const UInt8 *)[[dst stringByDeletingLastPathComponent] fileSystemRepresentation], &tmpDirRef, NULL);
    }

    err = FSPathMakeRef((const UInt8 *)[[dst stringByDeletingLastPathComponent] fileSystemRepresentation], &dstDirRef, NULL);

	if (err == noErr && hadFileAtDest)
	{
        NSFileManager *manager = [[NSFileManager alloc] init];
        BOOL success = [manager moveItemAtPath:dst toPath:tmpPath error:error];
        if (!success && hadFileAtDest)
        {
            if (error != NULL)
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUFileCopyFailure userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Couldn't move %@ to %@.", dst, tmpPath] }];
            return NO;
        }
    }

    err = FSPathMakeRef((const UInt8 *)[src fileSystemRepresentation], &srcRef, NULL);
	if (err == noErr)
	{
        NSFileManager *manager = [[NSFileManager alloc] init];
        BOOL success = [manager copyItemAtPath:src toPath:dst error:error];
		if (!success)
		{
            // We better move the old version back to its old location
            if (hadFileAtDest) {
                success = [manager moveItemAtPath:tmpPath toPath:dst error:error];
            }
            if (!success && error != NULL)
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUFileCopyFailure userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Couldn't move %@ to %@.", dst, tmpPath] }];
            return NO;

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
    PerformOnMainThreadSync(^{
		[self releaseFromQuarantine:dst];
    });

    return YES;
}

@end

#include <dlfcn.h>
#include <errno.h>
#include <sys/xattr.h>

@implementation SUPlainInstaller (MMExtendedAttributes)

+ (int)removeXAttr:(NSString *)name
          fromFile:(NSString *)file
           options:(int)options
{
    // *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!

    const char *path = NULL;
    const char *attr = [name cStringUsingEncoding:NSASCIIStringEncoding];
    @try {
        path = [file fileSystemRepresentation];
    }
	@catch (id) {
        // -[NSString fileSystemRepresentation] throws an exception if it's
        // unable to convert the string to something suitable.  Map that to
        // EDOM, "argument out of domain", which sort of conveys that there
        // was a conversion failure.
        errno = EDOM;
        return -1;
    }

    return removexattr(path, attr, options);
}

+ (void)releaseFromQuarantine:(NSString *)root
{
    // *** MUST BE SAFE TO CALL ON NON-MAIN THREAD!

    NSFileManager *manager = [NSFileManager defaultManager];
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 101000
    if (!&NSURLQuarantinePropertiesKey) {
        NSString *const quarantineAttribute = (__bridge NSString *)kLSItemQuarantineProperties;
        const int removeXAttrOptions = XATTR_NOFOLLOW;

        [self removeXAttr:quarantineAttribute
                 fromFile:root
                  options:removeXAttrOptions];

        // Only recurse if it's actually a directory.  Don't recurse into a
        // root-level symbolic link.
        NSDictionary *rootAttributes = [manager attributesOfItemAtPath:root error:nil];
        NSString *rootType = rootAttributes[NSFileType];

        if (rootType == NSFileTypeDirectory) {
            // The NSDirectoryEnumerator will avoid recursing into any contained
            // symbolic links, so no further type checks are needed.
            NSDirectoryEnumerator *directoryEnumerator = [manager enumeratorAtPath:root];
            NSString *file = nil;
            while ((file = [directoryEnumerator nextObject])) {
                [self removeXAttr:quarantineAttribute
                         fromFile:[root stringByAppendingPathComponent:file]
                          options:removeXAttrOptions];
            }
        }
        return;
    }
#endif
    NSURL *rootURL = [NSURL fileURLWithPath:root];
    id rootResourceValue = nil;
    [rootURL getResourceValue:&rootResourceValue forKey:NSURLQuarantinePropertiesKey error:NULL];
    if (rootResourceValue) {
        [rootURL setResourceValue:[NSNull null] forKey:NSURLQuarantinePropertiesKey error:NULL];
    }
    
    // Only recurse if it's actually a directory.  Don't recurse into a
    // root-level symbolic link.
    NSDictionary *rootAttributes = [manager attributesOfItemAtPath:root error:nil];
    NSString *rootType = rootAttributes[NSFileType];

    if (rootType == NSFileTypeDirectory) {
        // The NSDirectoryEnumerator will avoid recursing into any contained
        // symbolic links, so no further type checks are needed.
        NSDirectoryEnumerator *directoryEnumerator = [manager enumeratorAtURL:rootURL includingPropertiesForKeys:nil options:(NSDirectoryEnumerationOptions)0 errorHandler:nil];

        for (NSURL *file in directoryEnumerator) {
            id fileResourceValue = nil;
            [file getResourceValue:&fileResourceValue forKey:NSURLQuarantinePropertiesKey error:NULL];
            if (fileResourceValue) {
                [file setResourceValue:[NSNull null] forKey:NSURLQuarantinePropertiesKey error:NULL];
            }
        }
    }
}

@end
