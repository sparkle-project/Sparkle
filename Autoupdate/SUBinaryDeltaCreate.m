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
@property (copy) NSString *relativePath;
@property (strong) NSString *resultPath;
@property (strong) NSNumber *oldPermissions;
@property (strong) NSNumber *permissions;
@property (strong) NSString *_fromPath;
@property (strong) NSString *_toPath;
- (id)initWithRelativePath:(NSString *)relativePath oldTree:(NSString *)oldTree newTree:(NSString *)newTree oldPermissions:(NSNumber *)oldPermissions newPermissions:(NSNumber *)permissions;
@end

@implementation CreateBinaryDeltaOperation
@synthesize relativePath = _relativePath;
@synthesize resultPath = _resultPath;
@synthesize oldPermissions = _oldPermissions;
@synthesize permissions = _permissions;
@synthesize _fromPath = _fromPath;
@synthesize _toPath = _toPath;

- (id)initWithRelativePath:(NSString *)relativePath oldTree:(NSString *)oldTree newTree:(NSString *)newTree oldPermissions:(NSNumber *)oldPermissions newPermissions:(NSNumber *)permissions
{
    if ((self = [super init])) {
        self.relativePath = relativePath;
        self.oldPermissions = oldPermissions;
        self.permissions = permissions;
        self._fromPath = [oldTree stringByAppendingPathComponent:relativePath];
        self._toPath = [newTree stringByAppendingPathComponent:relativePath];
    }
    return self;
}

- (void)main
{
    NSString *temporaryFile = temporaryFilename(@"BinaryDelta");
    const char *argv[] = { "/usr/bin/bsdiff", [self._fromPath fileSystemRepresentation], [self._toPath fileSystemRepresentation], [temporaryFile fileSystemRepresentation] };
    int result = bsdiff(4, argv);
    if (!result)
        self.resultPath = temporaryFile;
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
    if (originalInfoType != newInfoType) {
        // File types are different
        return YES;
    }

    NSString *originalPath = originalInfo[INFO_PATH_KEY];
    NSString *newPath = newInfo[INFO_PATH_KEY];

    // Skip delta if both entries are directories, or if the files/symlinks are equal in content
    if (originalInfoType == FTS_D || [[NSFileManager defaultManager] contentsEqualAtPath:originalPath andPath:newPath]) {
        // this is possible if just the permissions have changed but contents have not
        return YES;
    }

    return NO;
}

static BOOL shouldDeleteThenExtract(NSDictionary *originalInfo, NSDictionary *newInfo, SUBinaryDeltaMajorVersion majorVersion)
{
    if (!originalInfo) {
        return NO;
    }

    if ([(NSNumber *)originalInfo[INFO_TYPE_KEY] unsignedShortValue] != [(NSNumber *)newInfo[INFO_TYPE_KEY] unsignedShortValue]) {
        return YES;
    }
    
    // If the same file exists in both old and new trees and they have different content,
    // we should always issue deleting the old file before extracting the new
    // I believe xar container in version 2 format automatically did this if the file types were the same
    // but we don't want to rely on that implicitness
    if (MAJOR_VERSION_IS_AT_LEAST(majorVersion, SUBinaryDeltaMajorVersion3)) {
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

    if ([(NSNumber *)originalInfo[INFO_TYPE_KEY] unsignedShortValue] != [(NSNumber *)newInfo[INFO_TYPE_KEY] unsignedShortValue]) {
        return NO;
    }

    if ([(NSNumber *)originalInfo[INFO_PERMISSIONS_KEY] unsignedShortValue] == [(NSNumber *)newInfo[INFO_PERMISSIONS_KEY] unsignedShortValue]) {
        return NO;
    }

    return YES;
}

#define MIN_SIZE_FOR_CLONE 4096
static NSString *cloneableRelativePath(NSDictionary<NSString *, NSData *> *afterFileKeyToHashDictionary, NSDictionary<NSData *, NSArray<NSString *> *> *beforeHashToFileKeyDictionary, NSDictionary *originalTreeState, NSDictionary *newInfo, NSString *key, NSNumber * __autoreleasing *outPermissions)
{
    if (afterFileKeyToHashDictionary == nil) {
        return nil;
    }
    
    // Avoid clones for small files. Small files can compress very well, sometimes better than tracking clones.
    if ([(NSNumber *)newInfo[INFO_SIZE_KEY] unsignedLongLongValue] <= MIN_SIZE_FOR_CLONE) {
        return nil;
    }
    
    NSData *keyHash = afterFileKeyToHashDictionary[key];
    if (keyHash == nil) {
        return nil;
    }
    
    for (NSString *oldRelativePath in beforeHashToFileKeyDictionary[keyHash]) {
        NSDictionary *oldCloneInfo = originalTreeState[oldRelativePath];
        if (oldCloneInfo == nil) {
            continue;
        }
        
        if ([(NSNumber *)oldCloneInfo[INFO_TYPE_KEY] unsignedShortValue] != FTS_F || [(NSNumber *)newInfo[INFO_TYPE_KEY] unsignedShortValue] != FTS_F) {
            continue;
        }
        
        NSString *clonePath = oldCloneInfo[INFO_PATH_KEY];
        NSString *newPath = newInfo[INFO_PATH_KEY];
        
        if (![[NSFileManager defaultManager] contentsEqualAtPath:clonePath andPath:newPath]) {
            continue;
        }
        
        NSNumber *newPermissions = newInfo[INFO_PERMISSIONS_KEY];
        if ([(NSNumber *)oldCloneInfo[INFO_PERMISSIONS_KEY] unsignedShortValue] != [newPermissions unsignedShortValue]) {
            if (outPermissions != NULL) {
                *outPermissions = newPermissions;
            }
        }
        
        return oldRelativePath;
    }
    
    return nil;
}

BOOL createBinaryDelta(NSString *source, NSString *destination, NSString *patchFile, SUBinaryDeltaMajorVersion majorVersion, SPUDeltaCompressionMode compression, int32_t compressionLevel, BOOL verbose, NSError *__autoreleasing *error)
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
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Diffing code signed extended attributes are not supported. Detected extended attribute in before-tree on file %@", @(ent->fts_path)] }];
            }
            return NO;
        }
    }
    fts_close(fts);

    NSMutableDictionary<NSData *, NSMutableArray<NSString *> *> *beforeHashToFileKeyDictionary = MAJOR_VERSION_IS_AT_LEAST(majorVersion, SUBinaryDeltaMajorVersion3) ? [NSMutableDictionary dictionary] : nil;
    
    unsigned char beforeHash[CC_SHA1_DIGEST_LENGTH] = {0};
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

    while ((ent = fts_read(fts))) {
        if (ent->fts_info != FTS_F && ent->fts_info != FTS_SL && ent->fts_info != FTS_D) {
            continue;
        }

        NSString *key = pathRelativeToDirectory(destination, stringWithFileSystemRepresentation(ent->fts_path));
        if (![key length]) {
            continue;
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
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Diffing code signed extended attributes are not supported. Detected extended attribute in after-tree on file %@", @(ent->fts_path)] }];
            }
            return NO;
        }

        NSDictionary *oldInfo = originalTreeState[key];

        if ([info isEqual:oldInfo]) {
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

    NSMutableDictionary<NSString *, NSData *> *afterFileKeyToHashDictionary = MAJOR_VERSION_IS_AT_LEAST(majorVersion, SUBinaryDeltaMajorVersion3) ? [NSMutableDictionary dictionary] : nil;
    
    unsigned char afterHash[CC_SHA1_DIGEST_LENGTH] = {0};
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
        archive = [[SPUSparkleDeltaArchive alloc] initWithPatchFileForWriting:temporaryFile compression:compression compressionLevel:compressionLevel];
    } else {
        archive = [[SPUXarDeltaArchive alloc] initWithPatchFileForWriting:temporaryFile compression:compression compressionLevel:compressionLevel];
    }
    
    SPUDeltaArchiveHeader *header = [[SPUDeltaArchiveHeader alloc] initWithMajorVersion:majorVersion minorVersion:minorVersion beforeTreeHash:beforeHash afterTreeHash:afterHash];
    
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

    for (NSString *key in keys) {
        id value = [newTreeState valueForKey:key];

        if ([(NSObject *)value isEqual:[NSNull null]]) {
            [archive addItem:[[SPUDeltaArchiveItem alloc] initWithRelativeFilePath:key commands:SPUDeltaItemCommandDelete permissions:0]];

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
                    [archive addItem:[[SPUDeltaArchiveItem alloc] initWithRelativeFilePath:key commands:SPUDeltaItemCommandModifyPermissions permissions:[(NSNumber *)newInfo[INFO_PERMISSIONS_KEY] unsignedShortValue]]];

                    if (verbose) {
                        fprintf(stderr, "\n👮  %s %s (0%o -> 0%o)", VERBOSE_MODIFIED, [key fileSystemRepresentation], [(NSNumber *)originalInfo[INFO_PERMISSIONS_KEY] unsignedShortValue], [(NSNumber *)newInfo[INFO_PERMISSIONS_KEY] unsignedShortValue]);
                    }
                }
            } else {
                // Check if the new file can be cloned from an old existing one located at a different path
                NSNumber *newPermissionsFromClone = nil;
                NSString *clonedRelativePath = cloneableRelativePath(afterFileKeyToHashDictionary, beforeHashToFileKeyDictionary, originalTreeState, newInfo, key, &newPermissionsFromClone);
                if (clonedRelativePath != nil) {
                    SPUDeltaItemCommands commands = SPUDeltaItemCommandClone;
                    if (shouldDeleteThenExtract(originalInfo, newInfo, majorVersion)) {
                        commands |= SPUDeltaItemCommandDelete;
                    }
                    if (newPermissionsFromClone != nil) {
                        commands |= SPUDeltaItemCommandModifyPermissions;
                    }
                    
                    SPUDeltaArchiveItem *item = [[SPUDeltaArchiveItem alloc] initWithRelativeFilePath:key commands:commands permissions:newPermissionsFromClone.unsignedShortValue];
                    // Physical path for clones points to the old file
                    item.physicalFilePath = [source stringByAppendingPathComponent:clonedRelativePath];
                    item.clonedRelativePath = clonedRelativePath;
                    
                    [archive addItem:item];
                    
                    if (verbose) {
                        fprintf(stderr, "\n✂️   %s %s -> %s", VERBOSE_CLONED, [clonedRelativePath fileSystemRepresentation], [key fileSystemRepresentation]);
                    }
                } else {
                    // Otherwise add a new file
                    NSString *path = [destination stringByAppendingPathComponent:key];
                    
                    SPUDeltaItemCommands commands = shouldDeleteThenExtract(originalInfo, newInfo, majorVersion) ? (SPUDeltaItemCommandDelete | SPUDeltaItemCommandExtract) : SPUDeltaItemCommandExtract;
                    
                    SPUDeltaArchiveItem *item = [[SPUDeltaArchiveItem alloc] initWithRelativeFilePath:key commands:commands permissions:0];
                    item.physicalFilePath = path;
                    
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
            NSNumber *permissions =
                shouldChangePermissions(originalInfo, newInfo) ?
                newInfo[INFO_PERMISSIONS_KEY] :
                nil;
            CreateBinaryDeltaOperation *operation = [[CreateBinaryDeltaOperation alloc] initWithRelativePath:key oldTree:source newTree:destination oldPermissions:originalInfo[INFO_PERMISSIONS_KEY] newPermissions:permissions];
            [deltaQueue addOperation:operation];
            [deltaOperations addObject:operation];
        }
    }

    [deltaQueue waitUntilAllOperationsAreFinished];

    BOOL deltaOperationsFailed = NO;
    for (CreateBinaryDeltaOperation *operation in deltaOperations) {
        NSString *resultPath = [operation resultPath];
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

        if (verbose) {
            fprintf(stderr, "\n🔨  %s %s", VERBOSE_DIFFED, [[operation relativePath] fileSystemRepresentation]);
        }
        
        NSNumber *permissions = operation.permissions;
        NSString *relativePath = operation.relativePath;
        
        SPUDeltaItemCommands commands = (permissions != nil) ? (SPUDeltaItemCommandBinaryDiff | SPUDeltaItemCommandModifyPermissions) : SPUDeltaItemCommandBinaryDiff;
        
        SPUDeltaArchiveItem *item = [[SPUDeltaArchiveItem alloc] initWithRelativeFilePath:relativePath commands:commands permissions:permissions.unsignedShortValue];
        item.physicalFilePath = resultPath;
        
        [archive addItem:item];

        if (permissions != nil) {
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
        NSString *resultPath = [operation resultPath];
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
