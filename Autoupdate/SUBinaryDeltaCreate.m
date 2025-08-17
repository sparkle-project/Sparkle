//
//  SUBinaryDeltaCreate.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/9/15.
//  Copyright (c) 2015 Sparkle Project. All rights reserved.
//

#import "SUBinaryDeltaCreate.h"
#import <Foundation/Foundation.h>
#include "SUBinaryDeltaCommon.h"
#import "SPUDeltaArchiveProtocol.h"
#import "SPUSparkleDeltaArchive.h"
#import "SPUXarDeltaArchive.h"
#import <CommonCrypto/CommonDigest.h>
#include <fcntl.h>
#include <fts.h>
#include <libgen.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <unistd.h>
#include <sys/xattr.h>


#include "AppKitPrevention.h"

extern int bsdiff(int argc, const char **argv);

@interface CreateBinaryDeltaOperation : NSOperation

@property (nonatomic, copy, readonly) NSString *relativePath;
@property (nonatomic, copy, readonly) NSString *clonedRelativePath;
@property (nonatomic, readonly) NSString *resultPath;
@property (nonatomic, readonly) NSNumber *oldPermissions;
@property (nonatomic, readonly) NSNumber *permissions;
@property (nonatomic, readonly) NSString *fromPath;
@property (nonatomic, readonly) BOOL changingPermissions;

- (id)initWithRelativePath:(NSString *)relativePath clonedRelativePath:(NSString *)clonedRelativePath oldTree:(NSString *)oldTree newTree:(NSString *)newTree oldPermissions:(NSNumber *)oldPermissions newPermissions:(NSNumber *)permissions changingPermissions:(BOOL)changingPermissions SPU_OBJC_DIRECT;

@end

@implementation CreateBinaryDeltaOperation
{
    NSString *_toPath;
}

@synthesize relativePath = _relativePath;
@synthesize clonedRelativePath = _clonedRelativePath;
@synthesize resultPath = _resultPath;
@synthesize oldPermissions = _oldPermissions;
@synthesize permissions = _permissions;
@synthesize fromPath = _fromPath;
@synthesize changingPermissions = _changingPermissions;

- (id)initWithRelativePath:(NSString *)relativePath clonedRelativePath:(NSString *)clonedRelativePath oldTree:(NSString *)oldTree newTree:(NSString *)newTree oldPermissions:(NSNumber *)oldPermissions newPermissions:(NSNumber *)permissions changingPermissions:(BOOL)changingPermissions
{
    if ((self = [super init])) {
        _relativePath = [relativePath copy];
        _clonedRelativePath = [clonedRelativePath copy];
        _oldPermissions = oldPermissions;
        _permissions = permissions;
        _changingPermissions = changingPermissions;
        
        if (clonedRelativePath == nil) {
            _fromPath = [oldTree stringByAppendingPathComponent:relativePath];
        } else {
            _fromPath = [oldTree stringByAppendingPathComponent:clonedRelativePath];
        }
        _toPath = [newTree stringByAppendingPathComponent:relativePath];
    }
    return self;
}

- (void)main
{
    NSString *temporaryFile = temporaryFilename(@"BinaryDelta");
    const char *argv[] = { "/usr/bin/bsdiff", [_fromPath fileSystemRepresentation], [_toPath fileSystemRepresentation], [temporaryFile fileSystemRepresentation] };
    int result = bsdiff(4, argv);
    if (result == 0) {
        _resultPath = temporaryFile;
    }
}

@end

#define INFO_PATH_KEY @"path"
#define INFO_TYPE_KEY @"type"
#define INFO_PERMISSIONS_KEY @"permissions"
#define INFO_SIZE_KEY @"size"

static NSDictionary *infoForFile(FTSENT *ent)
{
    off_t size = (ent->fts_info != FTS_D) ? ent->fts_statp->st_size : 0;

    assert(ent->fts_statp != NULL);

    mode_t permissions = ent->fts_statp->st_mode & PERMISSION_FLAGS;

    NSString *path = @(ent->fts_path);
    assert(path != nil);
    
    return @{ INFO_PATH_KEY: path != nil ? path : @"",
              INFO_TYPE_KEY: @(ent->fts_info),
              INFO_PERMISSIONS_KEY: @(permissions),
              INFO_SIZE_KEY: @(size) };
}

static bool aclExists(const FTSENT *ent)
{
    // macOS does not currently support ACLs for symlinks
    if (ent->fts_info == FTS_SL) {
        return NO;
    }

    acl_t acl = acl_get_link_np(ent->fts_path, ACL_TYPE_EXTENDED);
    if (acl != NULL) {
        acl_entry_t entry;
        int result = acl_get_entry(acl, ACL_FIRST_ENTRY, &entry);
        assert(acl_free((void *)acl) == 0);
        return (result == 0);
    }
    return false;
}

static bool codeSignatureExtendedAttributeExists(const FTSENT *ent)
{
    const int options = XATTR_NOFOLLOW;
    ssize_t listSize = listxattr(ent->fts_path, NULL, 0, options);
    if (listSize == -1) {
        return false;
    }

    char *buffer = malloc((size_t)listSize);
    assert(buffer != NULL);

    ssize_t sizeBack = listxattr(ent->fts_path, buffer, (size_t)listSize, options);
    assert(sizeBack == listSize);

    size_t startCharacterIndex = 0;
    for (size_t characterIndex = 0; characterIndex < (size_t)listSize; characterIndex++) {
        if (buffer[characterIndex] == '\0') {
            char *attribute = &buffer[startCharacterIndex];
            size_t length = characterIndex - startCharacterIndex;
            if (strncmp(APPLE_CODE_SIGN_XATTR_CODE_DIRECTORY_KEY, attribute, length) == 0 || strncmp(APPLE_CODE_SIGN_XATTR_CODE_REQUIREMENTS_KEY, attribute, length) == 0 || strncmp(APPLE_CODE_SIGN_XATTR_CODE_SIGNATURE_KEY, attribute, length) == 0) {
                free(buffer);
                return true;
            }
            startCharacterIndex = characterIndex + 1;
        }
    }

    free(buffer);
    return false;
}

static NSString *absolutePath(NSString *path)
{
    NSURL *url = [[NSURL alloc] initFileURLWithPath:path];
    return [[url absoluteURL] path];
}

static NSString *temporaryPatchFile(NSString *patchFile)
{
    NSString *path = absolutePath(patchFile);
    NSString *directory = [path stringByDeletingLastPathComponent];
    NSString *file = [path lastPathComponent];
    return [NSString stringWithFormat:@"%@/.%@.tmp", directory, file];
}

#define MIN_FILE_SIZE_FOR_CREATING_DELTA 4096

static BOOL shouldSkipDeltaCompression(NSDictionary *originalInfo, NSDictionary *newInfo)
{
    unsigned long long fileSize = [(NSNumber *)newInfo[INFO_SIZE_KEY] unsignedLongLongValue];
    if (fileSize < MIN_FILE_SIZE_FOR_CREATING_DELTA) {
        return YES;
    }

    if (!originalInfo) {
        return YES;
    }

    unsigned short originalInfoType = [(NSNumber *)originalInfo[INFO_TYPE_KEY] unsignedShortValue];
    unsigned short newInfoType = [(NSNumber *)newInfo[INFO_TYPE_KEY] unsignedShortValue];
    if (originalInfoType != newInfoType || originalInfoType != FTS_F) {
        // File types are different or they're not regular files
        return YES;
    }

    NSString *originalPath = originalInfo[INFO_PATH_KEY];
    NSString *newPath = newInfo[INFO_PATH_KEY];

    // Skip delta if the files are equal in content
    if ([[NSFileManager defaultManager] contentsEqualAtPath:originalPath andPath:newPath]) {
        return YES;
    }

    return NO;
}

static BOOL shouldDeleteThenExtract(NSDictionary *originalInfo, NSDictionary *newInfo)
{
    if (!originalInfo) {
        return NO;
    }

    if ([(NSNumber *)originalInfo[INFO_TYPE_KEY] unsignedShortValue] != [(NSNumber *)newInfo[INFO_TYPE_KEY] unsignedShortValue]) {
        return YES;
    }

    return NO;
}

static BOOL shouldSkipExtracting(NSDictionary *originalInfo, NSDictionary *newInfo)
{
    if (!originalInfo) {
        return NO;
    }

    unsigned short originalInfoType = [(NSNumber *)originalInfo[INFO_TYPE_KEY] unsignedShortValue];
    unsigned short newInfoType = [(NSNumber *)newInfo[INFO_TYPE_KEY] unsignedShortValue];
    
    if (originalInfoType != newInfoType) {
        // File types are different
        return NO;
    }

    
    NSString *originalPath = originalInfo[INFO_PATH_KEY];
    NSString *newPath = newInfo[INFO_PATH_KEY];
    
    // Don't skip extract if files/symlinks entries are not equal in content
    // (note if the entries are directories, they are equal)
    if (originalInfoType != FTS_D && ![[NSFileManager defaultManager] contentsEqualAtPath:originalPath andPath:newPath]) {
        return NO;
    }

    return YES;
}

static BOOL shouldChangePermissions(NSDictionary *originalInfo, NSDictionary *newInfo)
{
    if (!originalInfo) {
        return NO;
    }
    
    unsigned short originalInfoType = [(NSNumber *)originalInfo[INFO_TYPE_KEY] unsignedShortValue];
    unsigned short newInfoType = [(NSNumber *)newInfo[INFO_TYPE_KEY] unsignedShortValue];

    if (originalInfoType != newInfoType) {
        return NO;
    }
    
    unsigned short oldPermissions = [(NSNumber *)originalInfo[INFO_PERMISSIONS_KEY] unsignedShortValue];
    unsigned short newPermissions = [(NSNumber *)newInfo[INFO_PERMISSIONS_KEY] unsignedShortValue];

    if (oldPermissions == newPermissions) {
        return NO;
    }
    
    // We don't track new permissions on symbolic links that aren't the 0755 macOS default
    // Some linux / remotely mounted filesystems may not track permissions on symlinks and use 0777
    // We don't want to pick up bad permissions
    if (newInfoType == FTS_SL && newPermissions != VALID_SYMBOLIC_LINK_PERMISSIONS) {
        return NO;
    }

    return YES;
}

#define MIN_SIZE_FOR_CLONE 4096
#define MIN_SIZE_FOR_CLONE_DIFF (4096 * 4)
static NSString *cloneableRelativePath(NSDictionary<NSString *, NSData *> *afterFileKeyToHashDictionary, NSDictionary<NSData *, NSArray<NSString *> *> *beforeHashToFileKeyDictionary, NSDictionary<NSString *, NSString *> *frameworkVersionsSubstitutes, NSDictionary<NSString *, NSString *> *fileSubstitutes, NSDictionary *originalTreeState, NSDictionary *newInfo, NSString *key, NSNumber * __autoreleasing *outNewPermissions, BOOL *clonePermissionsChanged, BOOL *clonedBinaryDiff)
{
    // Avoid clones for small files. Small files can compress very well, sometimes better than tracking clones.
    if ([(NSNumber *)newInfo[INFO_SIZE_KEY] unsignedLongLongValue] <= MIN_SIZE_FOR_CLONE) {
        return nil;
    }
    
    if ([(NSNumber *)newInfo[INFO_TYPE_KEY] unsignedShortValue] != FTS_F) {
        return nil;
    }
    
    {
        NSData *keyHash = afterFileKeyToHashDictionary[key];
        if (keyHash != nil) {
            // Check for identical clones first
            for (NSString *oldRelativePath in beforeHashToFileKeyDictionary[keyHash]) {
                NSDictionary *oldCloneInfo = originalTreeState[oldRelativePath];
                if (oldCloneInfo == nil) {
                    continue;
                }
                
                if ([(NSNumber *)oldCloneInfo[INFO_TYPE_KEY] unsignedShortValue] != FTS_F) {
                    continue;
                }
                
                NSString *clonePath = oldCloneInfo[INFO_PATH_KEY];
                NSString *newPath = newInfo[INFO_PATH_KEY];
                
                if (![[NSFileManager defaultManager] contentsEqualAtPath:clonePath andPath:newPath]) {
                    continue;
                }
                
                NSNumber *newPermissions = newInfo[INFO_PERMISSIONS_KEY];
                if (outNewPermissions != NULL) {
                    *outNewPermissions = newPermissions;
                }
                
                if (clonePermissionsChanged != NULL) {
                    *clonePermissionsChanged = ([(NSNumber *)oldCloneInfo[INFO_PERMISSIONS_KEY] unsignedShortValue] != [newPermissions unsignedShortValue]);
                }
                
                if (clonedBinaryDiff != NULL) {
                    *clonedBinaryDiff = NO;
                }
                
                return oldRelativePath;
            }
        }
    }
    
    // For non-identical files where we do a binary diff, make sure file size matches a more strict file size test
    if ([(NSNumber *)newInfo[INFO_SIZE_KEY] unsignedLongLongValue] <= MIN_SIZE_FOR_CLONE_DIFF) {
        return nil;
    }
    
    // Look out for any .framework/Versions/{A -> B} changes
    for (NSString *frameworkVersionPrefix in frameworkVersionsSubstitutes) {
        if (![key hasPrefix:frameworkVersionPrefix]) {
            continue;
        }
        
        NSString *cloneFrameworkSubstitutePrefix = frameworkVersionsSubstitutes[frameworkVersionPrefix];
        if (cloneFrameworkSubstitutePrefix == nil) {
            continue;
        }
        
        NSString *cloneRelativeKey = [key stringByReplacingCharactersInRange:NSMakeRange(0, frameworkVersionPrefix.length) withString:cloneFrameworkSubstitutePrefix];
        
        NSDictionary *oldCloneInfo = originalTreeState[cloneRelativeKey];
        if (oldCloneInfo == nil) {
            continue;
        }

        // The old file must have the same type as the new one
        if ([(NSNumber *)oldCloneInfo[INFO_TYPE_KEY] unsignedShortValue] != FTS_F) {
            continue;
        }

        NSNumber *newPermissions = newInfo[INFO_PERMISSIONS_KEY];
        if (outNewPermissions != NULL) {
            *outNewPermissions = newPermissions;
        }
        
        if (clonePermissionsChanged != NULL) {
            *clonePermissionsChanged = ([(NSNumber *)oldCloneInfo[INFO_PERMISSIONS_KEY] unsignedShortValue] != [newPermissions unsignedShortValue]);
        }
        
        if (clonedBinaryDiff != NULL) {
            *clonedBinaryDiff = YES;
        }
        
        return cloneRelativeKey;
    }
    
    // Look out for any changes that involve the same named file moving to another directory
    do {
        NSString *cloneRelativeKey = fileSubstitutes[key.lastPathComponent];
        if (cloneRelativeKey == nil) {
            break;
        }
        
        NSDictionary *oldCloneInfo = originalTreeState[cloneRelativeKey];
        if (oldCloneInfo == nil) {
            break;
        }
        
        uint64_t cloneSize = [(NSNumber *)oldCloneInfo[INFO_SIZE_KEY] unsignedLongValue];
        uint64_t newSize = [(NSNumber *)newInfo[INFO_SIZE_KEY] unsignedLongValue];
        uint64_t minSize = MIN(cloneSize, newSize);
        uint64_t maxSize = MAX(cloneSize, newSize);
        
        // Ensure file is at least 60% the same size
        if (minSize == 0 || maxSize == 0 || (double)minSize / (double)maxSize < 0.60) {
            break;
        }
        
        NSNumber *newPermissions = newInfo[INFO_PERMISSIONS_KEY];
        if (outNewPermissions != NULL) {
            *outNewPermissions = newPermissions;
        }
        
        if (clonePermissionsChanged != NULL) {
            *clonePermissionsChanged = ([(NSNumber *)oldCloneInfo[INFO_PERMISSIONS_KEY] unsignedShortValue] != [newPermissions unsignedShortValue]);
        }
        
        if (clonedBinaryDiff != NULL) {
            *clonedBinaryDiff = YES;
        }
        
        return cloneRelativeKey;
    } while (NO);
    
    return nil;
}

BOOL createBinaryDelta(NSString *source, NSString *destination, NSString *patchFile, SUBinaryDeltaMajorVersion majorVersion, SPUDeltaCompressionMode compression, uint8_t compressionLevel, BOOL verbose, NSError *__autoreleasing *error)
{
    assert(source);
    assert(destination);
    assert(patchFile);
    assert(majorVersion >= SUBinaryDeltaMajorVersionFirst && majorVersion <= SUBinaryDeltaMajorVersionLatest);

    uint16_t minorVersion = latestMinorVersionForMajorVersion(majorVersion);

    NSMutableDictionary *originalTreeState = [NSMutableDictionary dictionary];

    char pathBuffer[PATH_MAX] = { 0 };
    if (![source getFileSystemRepresentation:pathBuffer maxLength:sizeof(pathBuffer)]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to retrieve file system path representation from source %@", source] }];
        }
        return NO;
    }

    char *sourcePaths[] = { pathBuffer, 0 };
    FTS *fts = fts_open(sourcePaths, FTS_PHYSICAL | FTS_NOCHDIR, compareFiles);
    if (!fts) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"fts_open failed on source: %@", @(strerror(errno))] }];
        }
        return NO;
    }

    if (verbose) {
        fprintf(stderr, "Creating version %u.%u patch using %s compression...\n", majorVersion, minorVersion, deltaCompressionStringFromMode(compression).UTF8String);
        fprintf(stderr, "Processing source, %s...", [source fileSystemRepresentation]);
    }

    FTSENT *ent = 0;
    while ((ent = fts_read(fts))) {
        if (ent->fts_info != FTS_F && ent->fts_info != FTS_SL && ent->fts_info != FTS_D) {
            continue;
        }

        NSString *key = pathRelativeToDirectory(source, stringWithFileSystemRepresentation(ent->fts_path));
        if (![key length]) {
            continue;
        }
        
        if ([key isEqualToString:CUSTOM_ICON_PATH]) {
            if (verbose) {
                fprintf(stderr, "\n");
            }
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Diffing bundles with a custom icon set via a resource fork is not supported. Detected presence of %@", @(ent->fts_path)] }];
            }
            return NO;
        }

        NSDictionary *info = infoForFile(ent);
        if (!info) {
            if (verbose) {
                fprintf(stderr, "\n");
            }
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to retrieve info for file %@", @(ent->fts_path)] }];
            }
            return NO;
        }
        originalTreeState[key] = info;

        // Ensure Sparkle executable permissions are valid
        if (ent->fts_info == FTS_F && [key.lastPathComponent isEqualToString:@"Sparkle"] && [key.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent.lastPathComponent isEqualToString:@"Sparkle.framework"]) {
            mode_t permissions = (mode_t)[(NSNumber *)info[INFO_PERMISSIONS_KEY] shortValue];
            if (permissions != VALID_SPARKLE_EXECUTABLE_PERMISSIONS) {
                if (verbose) {
                    fprintf(stderr, "\n");
                }
                if (error != NULL) {
                    *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Permissions for Sparkle executable must be 0%o (found 0%o) on file %@", (unsigned int)VALID_SPARKLE_EXECUTABLE_PERMISSIONS, permissions, @(ent->fts_path)] }];
                }
                return NO;
            }
        }
        
        if (aclExists(ent)) {
            if (verbose) {
                fprintf(stderr, "\n");
            }
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Diffing ACLs are not supported. Detected ACL in before-tree on file %@", @(ent->fts_path)] }];
            }
            return NO;
        }

        if (codeSignatureExtendedAttributeExists(ent)) {
            if (verbose) {
                fprintf(stderr, "\n");
            }
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Diffing code signed extended attributes are not supported. Detected extended attribute in before-tree on file %@. For removing code signed extended attributes and improving your bundle's structure, please see https://developer.apple.com/documentation/bundleresources/placing_content_in_a_bundle", @(ent->fts_path)] }];
            }
            return NO;
        }
    }
    fts_close(fts);

    // This dictionary will help us keep track of clones
    NSMutableDictionary<NSData *, NSMutableArray<NSString *> *> *beforeHashToFileKeyDictionary = (majorVersion >= SUBinaryDeltaMajorVersion3) ? [NSMutableDictionary dictionary] : nil;
    
    unsigned char beforeHash[BINARY_DELTA_HASH_LENGTH] = {0};
    if (!getRawHashOfTreeAndFileTablesWithVersion(beforeHash, source, majorVersion, beforeHashToFileKeyDictionary, nil)) {
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to generate hash for tree %@", source] }];
        }
        return NO;
    }

    NSMutableDictionary *newTreeState = [NSMutableDictionary dictionary];
    for (NSString *key in originalTreeState) {
        newTreeState[key] = [NSNull null];
    }

    if (verbose) {
        fprintf(stderr, "\nProcessing destination, %s...", [destination fileSystemRepresentation]);
    }

    pathBuffer[0] = 0;
    if (![destination getFileSystemRepresentation:pathBuffer maxLength:sizeof(pathBuffer)]) {
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadInvalidFileNameError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to retrieve file system path representation from destination %@", destination] }];
        }
        return NO;
    }

    sourcePaths[0] = pathBuffer;
    fts = fts_open(sourcePaths, FTS_PHYSICAL | FTS_NOCHDIR, compareFiles);
    if (!fts) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"fts_open failed on destination: %@", @(strerror(errno))] }];
        }
        return NO;
    }
    
    bool foundFilesystemCompression = false;

    uint32_t warningsCount = 0;
    const uint32_t maxWarningsToPrint = 16;
    while ((ent = fts_read(fts))) {
        if (ent->fts_info != FTS_F && ent->fts_info != FTS_SL && ent->fts_info != FTS_D) {
            continue;
        }

        NSString *key = pathRelativeToDirectory(destination, stringWithFileSystemRepresentation(ent->fts_path));
        if (![key length]) {
            continue;
        }
        
        if ([key isEqualToString:CUSTOM_ICON_PATH]) {
            if (verbose) {
                fprintf(stderr, "\n");
            }
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Diffing bundles with a custom icon set via a resource fork is not supported. Detected presence of %@", @(ent->fts_path)] }];
            }
            return NO;
        }

        NSDictionary *info = infoForFile(ent);
        if (!info) {
            if (verbose) {
                fprintf(stderr, "\n");
            }
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to retrieve info from file %@", @(ent->fts_path)] }];
            }
            return NO;
        }

        // Ensure Sparkle executable permissions are valid
        if (ent->fts_info == FTS_F && [key.lastPathComponent isEqualToString:@"Sparkle"] && [key.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent.stringByDeletingLastPathComponent.lastPathComponent isEqualToString:@"Sparkle.framework"]) {
            mode_t permissions = (mode_t)[(NSNumber *)info[INFO_PERMISSIONS_KEY] shortValue];
            if (permissions != VALID_SPARKLE_EXECUTABLE_PERMISSIONS) {
                if (verbose) {
                    fprintf(stderr, "\n");
                }
                if (error != NULL) {
                    *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Permissions for Sparkle executable must be 0%o (found 0%o) on file %@", (unsigned int)VALID_SPARKLE_EXECUTABLE_PERMISSIONS, permissions, @(ent->fts_path)] }];
                }
                return NO;
            }
        }
        
        // We should validate ACLs even if we don't store the info in the diff in the case of ACLs
        // We should also not allow files with code signed extended attributes since Apple doesn't recommend inserting these
        // inside an application, and since we don't preserve extended attribitutes anyway

        if (aclExists(ent)) {
            if (verbose) {
                fprintf(stderr, "\n");
            }
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Diffing ACLs are not supported. Detected ACL in after-tree on file %@", @(ent->fts_path)] }];
            }
            return NO;
        }

        if (codeSignatureExtendedAttributeExists(ent)) {
            if (verbose) {
                fprintf(stderr, "\n");
            }
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Diffing code signed extended attributes are not supported. Detected extended attribute in after-tree on file %@. For removing code signed extended attributes and improving your bundle's structure, please see https://developer.apple.com/documentation/bundleresources/placing_content_in_a_bundle", @(ent->fts_path)] }];
            }
            return NO;
        }
        
        if (warningsCount < maxWarningsToPrint) {
            uint16_t permissions = (ent->fts_statp->st_mode & PERMISSION_FLAGS);
            if (ent->fts_info == FTS_SL) {
                if (permissions != VALID_SYMBOLIC_LINK_PERMISSIONS) {
                    fprintf(stderr, "\nWarning: file permissions 0%o of symbolic link '%s' won't be preserved in the delta update (only permissions with mode 0755 are supported for symbolic links).", permissions, ent->fts_path);
                    
                    warningsCount++;
                }
            } else if (permissions != 0755 && permissions != 0644) {
                // This could indicate something is wrong inside of the bundle so it's worth warning the user about
                fprintf(stderr, "\nWarning: detected irregular file permissions 0%o for '%s'", permissions, ent->fts_path);
                
                warningsCount++;
            }
            
            if (warningsCount == maxWarningsToPrint) {
                fprintf(stderr, "\nWarning: encountered too many warnings.. Ignoring the rest..");
            }
        }
        
        // If we find any executable files that are using file system compression, that is sufficient
        // for recording that the applier should re-apply file system compression.
        // We check for executable files because they are likely candidates to be compressed.
        if (!foundFilesystemCompression && (majorVersion >= SUBinaryDeltaMajorVersion3) && ent->fts_info == FTS_F && (ent->fts_statp->st_mode & (S_IXUSR | S_IXGRP | S_IXOTH)) != 0 && (ent->fts_statp->st_flags & UF_COMPRESSED) != 0) {
            foundFilesystemCompression = true;
            
            if (verbose) {
                fprintf(stderr, " File system compression detected.");
            }
        }

        NSDictionary *oldInfo = originalTreeState[key];

        BOOL hasEqualInfo;
        if (![info isEqual:oldInfo]) {
            hasEqualInfo = NO;
        } else {
            NSString *originalPath = oldInfo[INFO_PATH_KEY];
            NSString *newPath = info[INFO_PATH_KEY];
            hasEqualInfo = [[NSFileManager defaultManager] contentsEqualAtPath:originalPath andPath:newPath];
        }
        
        if (hasEqualInfo) {
            [newTreeState removeObjectForKey:key];
        } else {
            newTreeState[key] = info;

            if (oldInfo && [(NSNumber *)oldInfo[INFO_TYPE_KEY] unsignedShortValue] == FTS_D && [(NSNumber *)info[INFO_TYPE_KEY] unsignedShortValue] != FTS_D) {
                NSArray *parentPathComponents = key.pathComponents;

                for (NSString *childPath in originalTreeState) {
                    NSArray *childPathComponents = childPath.pathComponents;
                    if (childPathComponents.count > parentPathComponents.count &&
                        [parentPathComponents isEqualToArray:[childPathComponents subarrayWithRange:NSMakeRange(0, parentPathComponents.count)]]) {
                        [newTreeState removeObjectForKey:childPath];
                    }
                }
            }
        }
    }
    fts_close(fts);

    // This dictionary will help us keep track of clones
    NSMutableDictionary<NSString *, NSData *> *afterFileKeyToHashDictionary = (majorVersion >= SUBinaryDeltaMajorVersion3) ? [NSMutableDictionary dictionary] : nil;
    
    unsigned char afterHash[BINARY_DELTA_HASH_LENGTH] = {0};
    if (!getRawHashOfTreeAndFileTablesWithVersion(afterHash, destination, majorVersion, nil, afterFileKeyToHashDictionary)) {
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to generate hash for tree %@", destination] }];
        }
        return NO;
    }

    if (verbose) {
        fprintf(stderr, "\nGenerating delta...");
    }

    NSString *temporaryFile = temporaryPatchFile(patchFile);
    if (verbose) {
        fprintf(stderr, "\nWriting to temporary file %s...", [temporaryFile fileSystemRepresentation]);
    }
    
    id<SPUDeltaArchiveProtocol> archive;
    if (majorVersion >= SUBinaryDeltaMajorVersion3) {
        archive = [[SPUSparkleDeltaArchive alloc] initWithPatchFileForWriting:temporaryFile];
    } else {
#if SPARKLE_BUILD_LEGACY_DELTA_SUPPORT
        archive = [[SPUXarDeltaArchive alloc] initWithPatchFileForWriting:temporaryFile];
#else
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: @"Support for creating legacy delta updates is disabled" }];
        }
        return NO;
#endif
    }
    
    // Record creation date of root bundle item
    NSDate *bundleCreationDate;
    if (majorVersion >= SUBinaryDeltaMajorVersion4) {
        NSError *fileAttributesError = nil;
        NSDictionary<NSFileAttributeKey, id> *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:destination error:&fileAttributesError];
        
        if (fileAttributes != nil) {
            bundleCreationDate = fileAttributes[NSFileCreationDate];
        } else {
            bundleCreationDate = nil;
            fprintf(stderr, "\nWarning: unable to retrieve file creation date of new bundle: %s", fileAttributesError.localizedDescription.UTF8String);
        }
    } else {
        bundleCreationDate = nil;
    }
    
    SPUDeltaArchiveHeader *header = [[SPUDeltaArchiveHeader alloc] initWithCompression:compression compressionLevel:compressionLevel fileSystemCompression:foundFilesystemCompression majorVersion:majorVersion minorVersion:minorVersion beforeTreeHash:beforeHash afterTreeHash:afterHash bundleCreationDate:bundleCreationDate];
    
    [archive writeHeader:header];
    if (archive.error != nil) {
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = archive.error;
        }
        return NO;
    }

    NSOperationQueue *deltaQueue = [[NSOperationQueue alloc] init];
    NSMutableArray *deltaOperations = [NSMutableArray array];

    // Sort the keys by preferring the ones from the original tree to appear first
    // We want to enforce deleting before extracting in the case paths differ only by case
    NSArray *keys = [[newTreeState allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *key1, NSString *key2) {
      NSComparisonResult insensitiveCompareResult = [key1 caseInsensitiveCompare:key2];
      if (insensitiveCompareResult != NSOrderedSame) {
          return insensitiveCompareResult;
      }

      return originalTreeState[key1] ? NSOrderedAscending : NSOrderedDescending;
    }];
    
    // Using a couple of heuristics we track if files have been moved to other locations within the app bundle
    NSMutableDictionary<NSString *, NSString *> *frameworkVersionsSubstitutes = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSString *> *fileSubstitutes = [NSMutableDictionary dictionary];
    if (majorVersion >= SUBinaryDeltaMajorVersion3) {
        // Heuristic #1: track if an old framework version was removed and a new framework version was added
        // Keep track of these prefixes in a dictionary
        // Eg: /Contents/Frameworks/Foo.framework/Versions/B/ (new) -> /Contents/Frameworks/Foo.framework/Versions/A/ (old)
        
        NSMutableDictionary<NSString *, NSString *> *oldFrameworkVersions = [NSMutableDictionary dictionary];
        for (NSString *key in keys) {
            id value = [newTreeState valueForKey:key];
            if (![(NSObject *)value isEqual:[NSNull null]]) {
                continue;
            }
            
            NSDictionary *originalInfo = originalTreeState[key];
            if ([(NSNumber *)originalInfo[INFO_TYPE_KEY] unsignedShortValue] != FTS_D) {
                continue;
            }
            
            NSString *keyWithoutLastPathComponent = key.stringByDeletingLastPathComponent;
            
            if (![keyWithoutLastPathComponent.lastPathComponent isEqualToString:@"Versions"]) {
                continue;
            }
            
            NSString *keyWithoutLastLastPathComponent = keyWithoutLastPathComponent.stringByDeletingLastPathComponent;
            
            if (![keyWithoutLastLastPathComponent.pathExtension isEqualToString:@"framework"]) {
                continue;
            }
            
            oldFrameworkVersions[keyWithoutLastLastPathComponent] = key;
        }
        
        for (NSString *key in keys) {
            id value = [newTreeState valueForKey:key];
            if ([(NSObject *)value isEqual:[NSNull null]] || originalTreeState[key] != nil) {
                continue;
            }
            
            NSDictionary *newInfo = value;
            if ([(NSNumber *)newInfo[INFO_TYPE_KEY] unsignedShortValue] != FTS_D) {
                continue;
            }
            
            NSString *keyWithoutLastPathComponent = key.stringByDeletingLastPathComponent;
            
            if (![keyWithoutLastPathComponent.lastPathComponent isEqualToString:@"Versions"]) {
                continue;
            }
            
            NSString *keyWithoutLastLastPathComponent = keyWithoutLastPathComponent.stringByDeletingLastPathComponent;
            
            if (![keyWithoutLastLastPathComponent.pathExtension isEqualToString:@"framework"]) {
                continue;
            }
            
            NSString *oldFrameworkVersionKey = oldFrameworkVersions[keyWithoutLastLastPathComponent];
            if (oldFrameworkVersionKey == nil) {
                continue;
            }
            
            frameworkVersionsSubstitutes[[key stringByAppendingString:@"/"]] = [oldFrameworkVersionKey stringByAppendingString:@"/"];
        }
        
        // Heuristic #2: Keep a table of removed filenames, collapsing them by the largest file per unique name
        // This sees if a file has just been moved to another location
        for (NSString *key in keys) {
            id value = [newTreeState valueForKey:key];
            if (![(NSObject *)value isEqual:[NSNull null]]) {
                continue;
            }
            
            NSDictionary *keyInfo = originalTreeState[key];
            if ([(NSNumber *)keyInfo[INFO_TYPE_KEY] unsignedShortValue] != FTS_F) {
                continue;
            }
            
            NSString *lastPathComponent = key.lastPathComponent;
            
            NSString *existingKey = fileSubstitutes[lastPathComponent];
            if (existingKey == nil) {
                fileSubstitutes[lastPathComponent] = key;
            } else {
                NSDictionary *existingKeyInfo = originalTreeState[existingKey];
                if ([(NSNumber *)keyInfo[INFO_SIZE_KEY] unsignedLongValue] > [(NSNumber *)existingKeyInfo[INFO_SIZE_KEY] unsignedLongValue]) {
                    fileSubstitutes[lastPathComponent] = key;
                }
            }
        }
    }

    for (NSString *key in keys) {
        id value = [newTreeState valueForKey:key];

        if ([(NSObject *)value isEqual:[NSNull null]]) {
            [archive addItem:[[SPUDeltaArchiveItem alloc] initWithRelativeFilePath:key commands:SPUDeltaItemCommandDelete mode:0]];

            if (verbose) {
                fprintf(stderr, "\n❌  %s %s", VERBOSE_REMOVED, [key fileSystemRepresentation]);
            }
            continue;
        }

        NSDictionary *originalInfo = originalTreeState[key];
        NSDictionary *newInfo = newTreeState[key];
        if (shouldSkipDeltaCompression(originalInfo, newInfo)) {
            if (shouldSkipExtracting(originalInfo, newInfo)) {
                if (shouldChangePermissions(originalInfo, newInfo)) {
                    [archive addItem:[[SPUDeltaArchiveItem alloc] initWithRelativeFilePath:key commands:SPUDeltaItemCommandModifyPermissions mode:[(NSNumber *)newInfo[INFO_PERMISSIONS_KEY] unsignedShortValue]]];

                    if (verbose) {
                        fprintf(stderr, "\n👮  %s %s (0%o -> 0%o)", VERBOSE_MODIFIED, [key fileSystemRepresentation], [(NSNumber *)originalInfo[INFO_PERMISSIONS_KEY] unsignedShortValue], [(NSNumber *)newInfo[INFO_PERMISSIONS_KEY] unsignedShortValue]);
                    }
                }
            } else {
                // Check if the new file can be cloned from an old existing one located at a different path
                NSNumber *newPermissions = nil;
                BOOL clonePermissionsChanged = NO;
                BOOL clonedBinaryDiff = NO;
                NSString *clonedRelativePath = (majorVersion >= SUBinaryDeltaMajorVersion3) ? cloneableRelativePath(afterFileKeyToHashDictionary, beforeHashToFileKeyDictionary, frameworkVersionsSubstitutes, fileSubstitutes, originalTreeState, newInfo, key, &newPermissions, &clonePermissionsChanged, &clonedBinaryDiff) : nil;
                if (clonedRelativePath != nil) {
                    if (clonedBinaryDiff) {
                        NSDictionary *cloneInfo = originalTreeState[clonedRelativePath];
                        
                        CreateBinaryDeltaOperation *operation = [[CreateBinaryDeltaOperation alloc] initWithRelativePath:key clonedRelativePath:clonedRelativePath oldTree:source newTree:destination oldPermissions:cloneInfo[INFO_PERMISSIONS_KEY] newPermissions:newPermissions changingPermissions:clonePermissionsChanged];
                        [deltaQueue addOperation:operation];
                        [deltaOperations addObject:operation];
                    } else {
                        SPUDeltaItemCommands commands = SPUDeltaItemCommandClone;
                        if (clonePermissionsChanged) {
                            commands |= SPUDeltaItemCommandModifyPermissions;
                        }
                        
                        SPUDeltaArchiveItem *item = [[SPUDeltaArchiveItem alloc] initWithRelativeFilePath:key commands:commands mode:(clonePermissionsChanged ? newPermissions.unsignedShortValue : 0)];
                        // Physical path for clones points to the old file
                        item.itemFilePath = [source stringByAppendingPathComponent:clonedRelativePath];
                        item.sourcePath = item.itemFilePath;
                        item.clonedRelativePath = clonedRelativePath;
                        
                        [archive addItem:item];
                        
                        if (verbose) {
                            fprintf(stderr, "\n✂️   %s %s -> %s", VERBOSE_CLONED, [clonedRelativePath fileSystemRepresentation], [key fileSystemRepresentation]);
                        }
                    }
                } else {
                    // Otherwise add a new file
                    NSString *path = [destination stringByAppendingPathComponent:key];
                    
                    SPUDeltaItemCommands commands = SPUDeltaItemCommandExtract;
                    if (shouldDeleteThenExtract(originalInfo, newInfo)) {
                        commands |= SPUDeltaItemCommandDelete;
                    }
                    
                    SPUDeltaArchiveItem *item = [[SPUDeltaArchiveItem alloc] initWithRelativeFilePath:key commands:commands mode:0];
                    item.itemFilePath = path;
                    item.sourcePath = path;
                    
                    [archive addItem:item];

                    if (verbose) {
                        if (originalInfo) {
                            fprintf(stderr, "\n✏️  %s %s", VERBOSE_UPDATED, [key fileSystemRepresentation]);
                        } else {
                            fprintf(stderr, "\n✅  %s %s", VERBOSE_ADDED, [key fileSystemRepresentation]);
                        }
                    }
                }
            }
        } else {
            NSNumber *permissions = newInfo[INFO_PERMISSIONS_KEY];
            
            CreateBinaryDeltaOperation *operation = [[CreateBinaryDeltaOperation alloc] initWithRelativePath:key clonedRelativePath:nil oldTree:source newTree:destination oldPermissions:originalInfo[INFO_PERMISSIONS_KEY] newPermissions:permissions changingPermissions:shouldChangePermissions(originalInfo, newInfo)];
            [deltaQueue addOperation:operation];
            [deltaOperations addObject:operation];
        }
    }

    [deltaQueue waitUntilAllOperationsAreFinished];

    BOOL deltaOperationsFailed = NO;
    for (CreateBinaryDeltaOperation *operation in deltaOperations) {
        NSString *resultPath = operation.resultPath;
        if (resultPath == nil) {
            if (verbose) {
                fprintf(stderr, "\n");
            }
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to create patch from source %@ and destination %@", operation.relativePath, resultPath] }];
            }
            deltaOperationsFailed = YES;
            break;
        }

        NSString *clonedRelativePath = [operation clonedRelativePath];
        if (verbose) {
            if (clonedRelativePath == nil) {
                fprintf(stderr, "\n🔨  %s %s", VERBOSE_DIFFED, [[operation relativePath] fileSystemRepresentation]);
            } else {
                fprintf(stderr, "\n🔨  %s %s -> %s", VERBOSE_DIFFED, [clonedRelativePath fileSystemRepresentation], [[operation relativePath] fileSystemRepresentation]);
            }
        }
        
        NSNumber *mode = operation.permissions;
        NSString *relativePath = operation.relativePath;
        
        SPUDeltaItemCommands commands = SPUDeltaItemCommandBinaryDiff;
        if (operation.changingPermissions) {
            commands |= SPUDeltaItemCommandModifyPermissions;
        }
        if (clonedRelativePath != nil) {
            commands |= SPUDeltaItemCommandClone;
        }
        
        SPUDeltaArchiveItem *item = [[SPUDeltaArchiveItem alloc] initWithRelativeFilePath:relativePath commands:commands mode:mode.unsignedShortValue];
        item.itemFilePath = resultPath;
        item.sourcePath = operation.fromPath;
        item.clonedRelativePath = clonedRelativePath;
        
        [archive addItem:item];

        if (operation.changingPermissions) {
            if (verbose) {
                fprintf(stderr, "\n👮  %s %s (0%o -> 0%o)", VERBOSE_MODIFIED, relativePath.fileSystemRepresentation, operation.oldPermissions.unsignedShortValue, operation.permissions.unsignedShortValue);
            }
        }
    }
    
    if (!deltaOperationsFailed) {
        [archive finishEncodingItems];
    }
    
    [archive close];
    
    // Clean up operations after the archive has finished encoding
    for (CreateBinaryDeltaOperation *operation in deltaOperations) {
        NSString *resultPath = operation.resultPath;
        if (resultPath != nil) {
            unlink(resultPath.fileSystemRepresentation);
        }
    }
    
    if (deltaOperationsFailed) {
        // We already set an error so let's bail
        return NO;
    }
    
    NSError *archiveError = archive.error;
    if (archiveError != nil) {
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = archiveError;
        }
        return NO;
    }

    NSFileManager *filemgr;
    filemgr = [NSFileManager defaultManager];
    
    [filemgr removeItemAtPath: patchFile error: NULL];
    if ([filemgr moveItemAtPath: temporaryFile toPath: patchFile error: NULL]  != YES)
    {
        if (verbose) {
            fprintf(stderr, "Failed to move temporary file, %s, to %s!\n", [temporaryFile fileSystemRepresentation], [patchFile fileSystemRepresentation]);
        }
        return NO;
    }
    if (verbose) {
        fprintf(stderr, "\nDone!\n");
    }
    return YES;
}
