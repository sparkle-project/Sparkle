//
//  SUFileManager.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/18/15.
//  Copyright (c) 2015 zgcoder. All rights reserved.
//

#import "SUFileManager.h"
#import "SUHost.h"

#include <sys/xattr.h>
#include <sys/errno.h>
#include <sys/time.h>

static char SUAppleQuarantineIdentifier[] = "com.apple.quarantine";

// Authorization code based on generous contribution from Allan Odgaard. Thanks, Allan!
static BOOL AuthorizationExecuteWithPrivilegesAndWait(AuthorizationRef authorization, const char *executablePath, AuthorizationFlags options, char *const *arguments)
{
    sig_t oldSigChildHandler = signal(SIGCHLD, SIG_DFL);
    BOOL returnValue = YES;
    
#pragma clang diagnostic push
    // In the future, we may have to look at SMJobBless API to avoid deprecation. See issue #558
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (AuthorizationExecuteWithPrivileges(authorization, executablePath, options, arguments, NULL) == errAuthorizationSuccess)
#pragma clang diagnostic pop
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

// Used to indicate if the type of NSError requires us to attempt to peform the same operation again except with authentication
// To be safe, both read and write permission denied's are included because Cocoa's error methods are not very well documented
// and at least one case is caused from lack of read permissions (-[NSURL setResourceValue:forKey:error:])
#define NS_HAS_PERMISSION_ERROR(error) (error.code == NSFileReadNoPermissionError || error.code == NSFileWriteNoPermissionError)

#pragma clang diagnostic push
// Use direct access because it's easier, clearer, and faster
#pragma clang diagnostic ignored "-Wdirect-ivar-access"

@implementation SUFileManager
{
    AuthorizationRef _auth;
    NSFileManager *_fileManager;
}

- (id)init
{
    self = [super init];
    if (self != nil) {
        _fileManager = [[NSFileManager alloc] init];
    }
    return self;
}

// Acquires an authorization reference which is intended to be used for future authorized file operations
- (BOOL)_acquireAuthorizationWithError:(NSError *__autoreleasing *)error
{
    // No need to continue if we already acquired an authorization reference
    if (_auth != NULL) {
        return YES;
    }
    
    OSStatus status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment, kAuthorizationFlagDefaults, &_auth);
    if (status != errAuthorizationSuccess) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed creating authorization reference with status code %d.", status] }];
        }
        _auth = NULL;
        return NO;
    }
    return YES;
}

- (void)dealloc
{
    if (_auth != NULL) {
        AuthorizationFree(_auth, kAuthorizationFlagDefaults);
    }
}

// -[NSFileManager attributesOfItemAtPath:error:] won't follow symbolic links

- (BOOL)_itemExistsAtURL:(NSURL *)fileURL
{
    NSString *path = fileURL.path;
    if (path == nil) {
        return NO;
    }
    return [_fileManager attributesOfItemAtPath:path error:NULL] != nil;
}

- (BOOL)_itemExistsAtURL:(NSURL *)fileURL isDirectory:(BOOL *)isDirectory
{
    NSString *path = fileURL.path;
    if (path == nil) {
        return NO;
    }
    
    NSDictionary *attributes = [_fileManager attributesOfItemAtPath:path error:NULL];
    if (attributes == nil) {
        return NO;
    }
    
    if (isDirectory != NULL) {
        *isDirectory = [attributes[NSFileType] isEqualToString:NSFileTypeDirectory];
    }
    
    return YES;
}

// Wrapper around getxattr()
- (ssize_t)_getXAttr:(const char *)name fromFile:(NSString *)file options:(int)options
{
    char path[PATH_MAX] = {0};
    if (![file getFileSystemRepresentation:path maxLength:sizeof(path)]) {
        errno = 0;
        return -1;
    }
    
    return getxattr(path, name, NULL, 0, 0, options);
}

// Wrapper around removexattr()
- (int)_removeXAttr:(const char *)attr fromFile:(NSString *)file options:(int)options
{
    char path[PATH_MAX] = {0};
    if (![file getFileSystemRepresentation:path maxLength:sizeof(path)]) {
        errno = 0;
        return -1;
    }
    
    return removexattr(path, attr, options);
}

#define XATTR_UTILITY_PATH "/usr/bin/xattr"
// Recursively remove an xattr at a specified root URL with authentication
- (BOOL)_removeXAttrWithAuthentication:(char *__nonnull)xattrName fromRootURL:(NSURL *)rootURL error:(NSError *__autoreleasing *)error
{
    // Because this is a system utility, it's fine to follow the symbolic link if one exists
    if (![_fileManager fileExistsAtPath:@(XATTR_UTILITY_PATH)]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: @"xattr utility does not exist on this system." }];
        }
        return NO;
    }
    
    char path[PATH_MAX] = {0};
    if (![rootURL.path getFileSystemRepresentation:path maxLength:sizeof(path)]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"File to remove (%@) cannot be represented as a valid file name.", rootURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    if (![self _acquireAuthorizationWithError:error]) {
        return NO;
    }
    
    BOOL success = AuthorizationExecuteWithPrivilegesAndWait(_auth, XATTR_UTILITY_PATH, kAuthorizationFlagDefaults, (char *[]){ "-s", "-r", "-d", xattrName, path, NULL });
    
    if (!success && error != NULL) {
        NSString *errorMessage = [NSString stringWithFormat:@"Authenticated extended attribute deletion for %@ failed on %@.", [NSString stringWithUTF8String:xattrName], rootURL.path.lastPathComponent];
        *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:@{ NSLocalizedDescriptionKey:errorMessage }];
    }
    
    return success;
}

- (BOOL)_releaseItemFromQuarantineAtRootURL:(NSURL *)rootURL allowingAuthentication:(BOOL)allowsAuthentication withQuarantineRetrieval:(BOOL (^)(NSURL *))quarantineRetrieval quarantineRemoval:(BOOL (^)(NSURL *, NSError * __autoreleasing *))quarantineRemoval isAccessError:(BOOL (^)(NSError *))isAccessError error:(NSError * __autoreleasing *)error
{
    if (![self _itemExistsAtURL:rootURL]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to remove quarantine because %@ does not exist.", rootURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    BOOL (^releasingQuarantineRequiredAuthentication)(NSURL *, BOOL *, BOOL *) = ^(NSURL *fileURL, BOOL *didReleaseQuarantine, BOOL *success) {
        BOOL removedQuarantine = NO;
        BOOL attemptedAuthentication = NO;
        
        if (quarantineRetrieval(fileURL)) {
            NSError *removalError = nil;
            if (quarantineRemoval(fileURL, &removalError)) {
                removedQuarantine = YES;
            } else {
                if (allowsAuthentication && isAccessError(removalError)) {
                    removedQuarantine = [self _removeXAttrWithAuthentication:SUAppleQuarantineIdentifier fromRootURL:rootURL error:error];
                    attemptedAuthentication = YES;
                } else {
                    if (success != NULL) {
                        // Make sure we haven't already run into an error
                        if (*success && error != NULL) {
                            *error = removalError;
                        }
                        // Fail, but still try to release other items from quarantine
                        *success = NO;
                    }
                }
            }
        }
        
        if (didReleaseQuarantine != NULL) {
            *didReleaseQuarantine = removedQuarantine;
        }
        
        return attemptedAuthentication;
    };
    
    BOOL success = YES;
    
    BOOL releasedRootQuarantine = NO;
    if (releasingQuarantineRequiredAuthentication(rootURL, &releasedRootQuarantine, &success)) {
        return releasedRootQuarantine;
    }
    
    // Only recurse if it's actually a directory.  Don't recurse into a
    // root-level symbolic link.
    NSString *rootURLPath = rootURL.path;
    NSDictionary *rootAttributes = [_fileManager attributesOfItemAtPath:rootURLPath error:nil];
    NSString *rootType = rootAttributes[NSFileType];
    
    if ([rootType isEqualToString:NSFileTypeDirectory]) {
        // The NSDirectoryEnumerator will avoid recursing into any contained
        // symbolic links, so no further type checks are needed.
        NSDirectoryEnumerator *directoryEnumerator = [_fileManager enumeratorAtURL:rootURL includingPropertiesForKeys:nil options:(NSDirectoryEnumerationOptions)0 errorHandler:nil];
        
        for (NSURL *file in directoryEnumerator) {
            BOOL releasedQuarantine = NO;
            if (releasingQuarantineRequiredAuthentication(file, &releasedQuarantine, &success)) {
                return releasedQuarantine;
            }
        }
    }
    
    return success;
}

// Removes the directory tree rooted at |root| from the file quarantine.
// The quarantine was introduced on OS X 10.5 and is described at:
//
// http://developer.apple.com/releasenotes/Carbon/RN-LaunchServices/index.html#apple_ref/doc/uid/TP40001369-DontLinkElementID_2
//
// If |root| is not a directory, then it alone is removed from the quarantine.
// Symbolic links, including |root| if it is a symbolic link, will not be
// traversed.

// Ordinarily, the quarantine is managed by calling LSSetItemAttribute
// to set the kLSItemQuarantineProperties attribute to a dictionary specifying
// the quarantine properties to be applied.  However, it does not appear to be
// possible to remove an item from the quarantine directly through any public
// Launch Services calls.  Instead, this method takes advantage of the fact
// that the quarantine is implemented in part by setting an extended attribute,
// "com.apple.quarantine", on affected files.  Removing this attribute is
// sufficient to remove files from the quarantine.

// This works by removing the quarantine extended attribute for every file we come across.
// We used to have code similar to the method below that used -[NSURL getResourceValue:forKey:error:] and -[NSURL setResourceValue:forKey:error:]
// However, those methods *really suck* - you can't rely on the return value from getting the resource value and if you set the resource value
// when the key isn't present, errors are spewed out to the console
- (BOOL)_releaseItemFromQuarantineAtRootURL:(NSURL *)rootURL allowingAuthentication:(BOOL)allowsAuthentication error:(NSError *__autoreleasing *)error
{
    static const int removeXAttrOptions = XATTR_NOFOLLOW;
    
    return
    [self
     _releaseItemFromQuarantineAtRootURL:rootURL
     allowingAuthentication:allowsAuthentication
     withQuarantineRetrieval:^BOOL(NSURL *fileURL) {
         return ([self _getXAttr:SUAppleQuarantineIdentifier fromFile:fileURL.path options:removeXAttrOptions] >= 0);
     }
     quarantineRemoval:^BOOL(NSURL *fileURL, NSError * __autoreleasing *removalError) {
         BOOL removedQuarantine = ([self _removeXAttr:SUAppleQuarantineIdentifier fromFile:fileURL.path options:removeXAttrOptions] == 0);
         if (!removedQuarantine && removalError != NULL) {
             *removalError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to remove file quarantine on %@.", fileURL.lastPathComponent] }];
         }
         return removedQuarantine;
     }
     isAccessError:^BOOL(NSError *removalError) {
         return (removalError.code == EACCES);
     }
     error:error];
}

- (BOOL)releaseItemFromQuarantineAtRootURL:(NSURL *)rootURL error:(NSError * __autoreleasing *)error
{
    return [self _releaseItemFromQuarantineAtRootURL:rootURL allowingAuthentication:YES error:error];
}

- (BOOL)releaseItemFromQuarantineWithoutAuthenticationAtRootURL:(NSURL *)rootURL error:(NSError * __autoreleasing *)error
{
    return [self _releaseItemFromQuarantineAtRootURL:rootURL allowingAuthentication:NO error:error];
}

- (BOOL)moveItemAtURL:(NSURL *)sourceURL toURL:(NSURL *)destinationURL error:(NSError *__autoreleasing *)error
{
    if (![self _itemExistsAtURL:sourceURL]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Source file to move (%@) does not exist.", sourceURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    if ([self _itemExistsAtURL:destinationURL]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteFileExistsError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Destination file to move (%@) already exists.", destinationURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    NSError *moveError = nil;
    if ([_fileManager moveItemAtURL:sourceURL toURL:destinationURL error:&moveError]) {
        return YES;
    }
    
    if (!NS_HAS_PERMISSION_ERROR(moveError)) {
        if (error != NULL) {
            *error = moveError;
        }
        return NO;
    }
    
    if (![self _acquireAuthorizationWithError:error]) {
        return NO;
    }
    
    char sourcePath[PATH_MAX] = {0};
    if (![sourceURL.path getFileSystemRepresentation:sourcePath maxLength:sizeof(sourcePath)]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"File to move (%@) cannot be represented as a valid file name.", sourceURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    char destinationPath[PATH_MAX] = {0};
    if (![destinationURL.path getFileSystemRepresentation:destinationPath maxLength:sizeof(destinationPath)]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Destination (%@) cannot be represented as a valid file name.", destinationURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    if (!AuthorizationExecuteWithPrivilegesAndWait(_auth, "/bin/mv", kAuthorizationFlagDefaults, (char *[]){ "-f", sourcePath, destinationPath, NULL })) {
        if (error != NULL) {
            NSString *errorMessage = [NSString stringWithFormat:@"Failed to perform authenticated file move for %@.", sourceURL.lastPathComponent];
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:@{ NSLocalizedDescriptionKey:errorMessage }];
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)_changeOwnerAndGroupOfItemAtURL:(NSURL *)targetURL ownerID:(NSNumber *)ownerID groupID:(NSNumber *)groupID needsAuth:(BOOL *)needsAuth error:(NSError * __autoreleasing *)error
{
    char path[PATH_MAX] = {0};
    if (![targetURL.path getFileSystemRepresentation:path maxLength:sizeof(path)]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"File to change owner & group (%@) cannot be represented as a valid file name.", targetURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    if (chown(path, ownerID.unsignedIntValue, groupID.unsignedIntValue) != 0) {
        if (errno == EPERM) {
            if (needsAuth != NULL) {
                *needsAuth = YES;
            }
        } else {
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to change owner & group for %@ with owner ID %u and group ID %u.", targetURL.path.lastPathComponent, ownerID.unsignedIntValue, groupID.unsignedIntValue] }];
            }
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)changeOwnerAndGroupOfItemAtRootURL:(NSURL *)targetURL toMatchURL:(NSURL *)matchURL error:(NSError * __autoreleasing *)error
{
    BOOL isTargetADirectory = NO;
    if (![self _itemExistsAtURL:targetURL isDirectory:&isTargetADirectory]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to change owner & group IDs because %@ does not exist.", targetURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    if (![self _itemExistsAtURL:matchURL]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to match owner & group IDs because %@ does not exist.", matchURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    NSError *matchFileAttributesError = nil;
    NSString *matchURLPath = matchURL.path;
    NSDictionary *matchFileAttributes = [_fileManager attributesOfItemAtPath:matchURLPath error:&matchFileAttributesError];
    if (matchFileAttributes == nil) {
        if (error != NULL) {
            *error = matchFileAttributesError;
        }
        return NO;
    }
    
    NSError *targetFileAttributesError = nil;
    NSString *targetURLPath = targetURL.path;
    NSDictionary *targetFileAttributes = [_fileManager attributesOfItemAtPath:targetURLPath error:&targetFileAttributesError];
    if (targetFileAttributes == nil) {
        if (error != NULL) {
            *error = targetFileAttributesError;
        }
        return NO;
    }
    
    NSNumber *ownerID = matchFileAttributes[NSFileOwnerAccountID];
    if (ownerID == nil) {
        // shouldn't be possible to error here, but just in case
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoPermissionError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Owner ID could not be read from %@.", matchURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    NSNumber *groupID = matchFileAttributes[NSFileGroupOwnerAccountID];
    if (groupID == nil) {
        // shouldn't be possible to error here, but just in case
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoPermissionError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Group ID could not be read from %@.", matchURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    NSNumber *targetOwnerID = targetFileAttributes[NSFileOwnerAccountID];
    NSNumber *targetGroupID = targetFileAttributes[NSFileGroupOwnerAccountID];
    
    if ((targetOwnerID != nil && [ownerID isEqualToNumber:targetOwnerID]) && (targetGroupID != nil && [groupID isEqualToNumber:targetGroupID])) {
        // Assume they're the same even if we don't check every file recursively
        // Speeds up the common case
        return YES;
    }
    
    BOOL needsAuth = NO;
    
    if (![self _changeOwnerAndGroupOfItemAtURL:targetURL ownerID:ownerID groupID:groupID needsAuth:&needsAuth error:error]) {
        return NO;
    }
    
    if (isTargetADirectory) {
        NSDirectoryEnumerator *directoryEnumerator = [_fileManager enumeratorAtURL:targetURL includingPropertiesForKeys:nil options:(NSDirectoryEnumerationOptions)0 errorHandler:nil];
        for (NSURL *url in directoryEnumerator) {
            if (![self _changeOwnerAndGroupOfItemAtURL:url ownerID:ownerID groupID:groupID needsAuth:&needsAuth error:error]) {
                return NO;
            }
            
            if (needsAuth) {
                break;
            }
        }
    }
    
    if (!needsAuth) {
        return YES;
    }
    
    char targetPath[PATH_MAX] = {0};
    if (![targetURL.path getFileSystemRepresentation:targetPath maxLength:sizeof(targetPath)]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Target file (%@) cannot be represented as a valid file name.", targetURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    char userAndGroup[100];
    int written = snprintf(userAndGroup, sizeof(userAndGroup), "%u:%u", ownerID.unsignedIntValue, groupID.unsignedIntValue);
    if (written < 0 || written >= 100) {
        return NO; // No custom error, because it's too unlikely to ever happen
    }
    
    if (![self _acquireAuthorizationWithError:error]) {
        return NO;
    }
    
    BOOL success = AuthorizationExecuteWithPrivilegesAndWait(_auth, "/usr/sbin/chown", kAuthorizationFlagDefaults, (char *[]){ "-R", userAndGroup, targetPath, NULL });
    if (!success && error != NULL) {
        NSString *errorMessage = [NSString stringWithFormat:@"Failed to change owner:group %@ on %@ with authentication.", [NSString stringWithUTF8String:userAndGroup], targetURL.path.lastPathComponent];
        *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:@{ NSLocalizedDescriptionKey: errorMessage }];
    }
    
    return success;
}

// /usr/bin/touch can be used to update an application, as described in:
// https://developer.apple.com/library/mac/documentation/Carbon/Conceptual/LaunchServicesConcepts/LSCConcepts/LSCConcepts.html
// The document says LSRegisterURL() can be used as well but this hasn't worked out well for me in practice
// Anyway, updating the modification time of the application is important because the system will be aware a new version of your app is available,
// Finder will report the correct file size and other metadata for it, URL schemes your app may register will be updated, etc.
// Behind the scenes, touch calls to utimes() which is what we use here - unless we need to authenticate
- (BOOL)updateModificationAndAccessTimeOfItemAtURL:(NSURL *)targetURL error:(NSError * __autoreleasing *)error
{
    if (![self _itemExistsAtURL:targetURL]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to update modification & access time because %@ does not exist.", targetURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    char path[PATH_MAX] = {0};
    if (![targetURL.path getFileSystemRepresentation:path maxLength:sizeof(path)]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"File to update modification & access time (%@) cannot be represented as a valid file name.", targetURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    if (utimes(path, NULL) == 0) {
        return YES;
    }
    
    if (errno != EACCES) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to update modification & access time for %@", targetURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    if (![self _acquireAuthorizationWithError:error]) {
        return NO;
    }
    
    BOOL success = AuthorizationExecuteWithPrivilegesAndWait(_auth, "/usr/bin/touch", kAuthorizationFlagDefaults, (char *[]){ path, NULL });
    if (!success && error != NULL) {
        NSString *errorMessage = [NSString stringWithFormat:@"Failed to update modification & access time on %@ with authentication.", targetURL.path.lastPathComponent];
        *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:@{ NSLocalizedDescriptionKey: errorMessage }];
    }
    
    return success;
}

// Creates a directory at the item pointed by url
// An item cannot already exist at the url, but the parent must be a directory that exists
- (BOOL)_makeDirectoryAtURL:(NSURL *)url error:(NSError * __autoreleasing *)error
{
    if ([self _itemExistsAtURL:url]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteFileExistsError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to create directory because file %@ already exists.", url.path.lastPathComponent] }];
        }
        return NO;
    }
    
    NSURL *parentURL = [url URLByDeletingLastPathComponent];
    BOOL isParentADirectory = NO;
    if (![self _itemExistsAtURL:parentURL isDirectory:&isParentADirectory] || !isParentADirectory) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to create directory because parent directory %@ does not exist.", parentURL.path.lastPathComponent] }];
        }
        return NO;
    }
    
    NSError *createDirectoryError = nil;
    if ([_fileManager createDirectoryAtURL:url withIntermediateDirectories:NO attributes:nil error:&createDirectoryError]) {
        return YES;
    }
    
    if (!NS_HAS_PERMISSION_ERROR(createDirectoryError)) {
        if (error != NULL) {
            *error = createDirectoryError;
        }
        return NO;
    }
    
    char path[PATH_MAX] = {0};
    if (![url.path getFileSystemRepresentation:path maxLength:sizeof(path)]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Directory to create (%@) cannot be represented as a valid file name.", url.path.lastPathComponent] }];
        }
        return NO;
    }
    
    if (![self _acquireAuthorizationWithError:error]) {
        return NO;
    }
    
    BOOL success = AuthorizationExecuteWithPrivilegesAndWait(_auth, "/bin/mkdir", kAuthorizationFlagDefaults, (char *[]){ path, NULL });
    if (!success && error != NULL) {
        NSString *errorMessage = [NSString stringWithFormat:@"Failed to make directory %@ with authentication.", url.path.lastPathComponent];
        *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:@{ NSLocalizedDescriptionKey: errorMessage }];
    }
    return success;
}

- (NSURL *)makeTemporaryDirectoryWithPreferredName:(NSString *)preferredName appropriateForDirectoryURL:(NSURL *)directoryURL error:(NSError * __autoreleasing *)error
{
    NSError *tempError = nil;
    NSURL *tempURL = [_fileManager URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask appropriateForURL:directoryURL create:YES error:&tempError];
    
    if (tempURL != nil) {
        return tempURL;
    }
    
    // It is pretty unlikely in my testing we will get here, but just in case we do, we should create a directory inside
    // the directory pointed by directoryURL, using the preferredName
    
    NSURL *desiredURL = [directoryURL URLByAppendingPathComponent:preferredName];
    NSUInteger tagIndex = 1;
    while ([self _itemExistsAtURL:desiredURL] && tagIndex <= 9999) {
        desiredURL = [directoryURL URLByAppendingPathComponent:[preferredName stringByAppendingFormat:@" (%lu)", (unsigned long)++tagIndex]];
    }
    
    return [self _makeDirectoryAtURL:desiredURL error:error] ? desiredURL : nil;
}

- (BOOL)removeItemAtURL:(NSURL *)url error:(NSError * __autoreleasing *)error
{
    if (![self _itemExistsAtURL:url]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to remove file %@ because it does not exist.", url.path.lastPathComponent] }];
        }
        return NO;
    }
    
    NSError *removeError = nil;
    if ([_fileManager removeItemAtURL:url error:&removeError]) {
        return YES;
    }
    
    if (!NS_HAS_PERMISSION_ERROR(removeError)) {
        if (error != NULL) {
            *error = removeError;
        }
        return NO;
    }
    
    if (![self _acquireAuthorizationWithError:error]) {
        return NO;
    }
    
    char path[PATH_MAX] = {0};
    if (![url.path getFileSystemRepresentation:path maxLength:sizeof(path)]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"File to remove (%@) cannot be represented as a valid file name.", url.path.lastPathComponent] }];
        }
        return NO;
    }
    
    BOOL success = AuthorizationExecuteWithPrivilegesAndWait(_auth, "/bin/rm", kAuthorizationFlagDefaults, (char *[]){ "-rf", path, NULL });
    if (!success && error != NULL) {
        *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAuthenticationFailure userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to remove %@ with authentication.", url.path.lastPathComponent] }];
    }
    return success;
}

- (BOOL)moveItemAtURLToTrash:(NSURL *)url error:(NSError *__autoreleasing *)error
{
    if (![self _itemExistsAtURL:url]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to move %@ to the trash because the file does not exist.", url.path.lastPathComponent] }];
        }
        return NO;
    }
    
    NSURL *trashURL = nil;
    BOOL canUseNewTrashAPI = YES;
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 1080
    canUseNewTrashAPI = [SUHost isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){10, 8, 0}];
    if (!canUseNewTrashAPI) {
        FSRef trashRef;
        if (FSFindFolder(kUserDomain, kTrashFolderType, kDontCreateFolder, &trashRef) == noErr) {
            trashURL = CFBridgingRelease(CFURLCreateFromFSRef(kCFAllocatorDefault, &trashRef));
        }
    }
#endif
    
    if (canUseNewTrashAPI) {
        trashURL = [_fileManager URLForDirectory:NSTrashDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
    }
    
    if (trashURL == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: @"Failed to locate the user's trash folder." }];
        }
        return NO;
    }
    
    // In the rare worst case scenario, our temporary directory will be labeled incomplete and be in the user's trash directory,
    // indicating that whatever inside of there is not yet completely moved.
    // Regardless, we want the item to be in our Volume before we try moving it to the trash
    NSString *preferredName = [url.lastPathComponent.stringByDeletingPathExtension stringByAppendingString:@" (Incomplete Files)"];
    NSURL *tempDirectory = [self makeTemporaryDirectoryWithPreferredName:preferredName appropriateForDirectoryURL:trashURL error:error];
    if (tempDirectory == nil) {
        return NO;
    }
    
    NSString *urlLastPathComponent = url.lastPathComponent;
    NSURL *tempItemURL = [tempDirectory URLByAppendingPathComponent:urlLastPathComponent];
    if (![self moveItemAtURL:url toURL:tempItemURL error:error]) {
        // If we can't move the item at url, just remove it completely; chances are it's not going to be missed
        [self removeItemAtURL:url error:NULL];
        [self removeItemAtURL:tempDirectory error:NULL];
        return NO;
    }
    
    if (![self changeOwnerAndGroupOfItemAtRootURL:tempItemURL toMatchURL:trashURL error:error]) {
        // Removing the item inside of the temp directory is better than trying to move the item to the trash with incorrect ownership
        [self removeItemAtURL:tempDirectory error:NULL];
        return NO;
    }
    
    // If we get here, we should be able to trash the item normally without authentication
    
    BOOL success = NO;
#if __MAC_OS_X_VERSION_MIN_REQUIRED < 1080
    if (!canUseNewTrashAPI) {
        NSString *tempParentPath = tempItemURL.URLByDeletingLastPathComponent.path;
        success = [[NSWorkspace sharedWorkspace] performFileOperation:NSWorkspaceRecycleOperation source:tempParentPath destination:@"" files:@[tempItemURL.lastPathComponent] tag:NULL];
        if (!success && error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to move file %@ into the trash.", tempItemURL.lastPathComponent] }];
        }
    }
#endif
    
    if (canUseNewTrashAPI) {
        NSError *trashError = nil;
        success = [_fileManager trashItemAtURL:tempItemURL resultingItemURL:NULL error:&trashError];
        if (!success && error != NULL) {
            *error = trashError;
        }
    }
    
    [self removeItemAtURL:tempDirectory error:NULL];
    
    return success;
}

@end

#pragma clang diagnostic pop
