//
//  SUBinaryDeltaCommon.m
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-01.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#include "SUBinaryDeltaCommon.h"
#import "SUFileManager.h"
#include <CommonCrypto/CommonDigest.h>
#include <Foundation/Foundation.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/param.h>
#include <sys/stat.h>

#include "AppKitPrevention.h"

// Note: the framework bundle version must be bumped, and generate_appcast must be updated to compare it,
// when we add/change new major versions and defaults
SUBinaryDeltaMajorVersion SUBinaryDeltaMajorVersionDefault = SUBinaryDeltaMajorVersion3;
SUBinaryDeltaMajorVersion SUBinaryDeltaMajorVersionLatest = SUBinaryDeltaMajorVersion3;
SUBinaryDeltaMajorVersion SUBinaryDeltaMajorVersionFirst = SUBinaryDeltaMajorVersion1;
SUBinaryDeltaMajorVersion SUBinaryDeltaMajorVersionFirstSupported = SUBinaryDeltaMajorVersion2;

SPUDeltaCompressionMode deltaCompressionModeFromDescription(NSString *requestedDescription, BOOL *requestValid)
{
    // Set to NO later if request was not valid
    if (requestValid != NULL) {
        *requestValid = YES;
    }
    
    SPUDeltaCompressionMode compression;
    NSString *description = requestedDescription.lowercaseString;
    
    if ([description isEqualToString:@"default"]) {
        compression = SPUDeltaCompressionModeDefault;
    } else if ([description isEqualToString:@"none"]) {
        compression = SPUDeltaCompressionModeNone;
    } else if ([description isEqualToString:@"bzip2"]) {
        compression = SPUDeltaCompressionModeBzip2;
    } else if ([description isEqualToString:@"lzma"]) {
        compression = SPUDeltaCompressionModeLZMA;
    } else if ([description isEqualToString:@"lzfse"]) {
        compression = SPUDeltaCompressionModeLZFSE;
    } else if ([description isEqualToString:@"lz4"]) {
        compression = SPUDeltaCompressionModeLZ4;
    } else if ([description isEqualToString:@"zlib"]) {
        compression = SPUDeltaCompressionModeZLIB;
    } else {
        compression = SPUDeltaCompressionModeDefault;
        
        if (requestValid != NULL) {
            *requestValid = NO;
        }
    }
    
    return compression;
}

NSString *deltaCompressionStringFromMode(SPUDeltaCompressionMode mode)
{
    switch (mode) {
        case SPUDeltaCompressionModeBzip2:
            return @"bzip2";
        case SPUDeltaCompressionModeLZMA:
            return @"LZMA";
        case SPUDeltaCompressionModeNone:
            return @"no";
        case SPUDeltaCompressionModeLZ4:
            return @"LZ4";
        case SPUDeltaCompressionModeLZFSE:
            return @"LZFSE";
        case SPUDeltaCompressionModeZLIB:
            return @"ZLIB";
        default:
            break;
    }
    
    if (mode == SPUDeltaCompressionModeDefault) {
        return @"default";
    }
    
    return @"unknown";
}

int compareFiles(const FTSENT **a, const FTSENT **b)
{
    return strcoll((*a)->fts_name, (*b)->fts_name);
}

NSString *pathRelativeToDirectory(NSString *directory, NSString *path)
{
    NSUInteger directoryLength = [directory length];
    if ([path hasPrefix:directory])
        return [path substringFromIndex:directoryLength];

    return path;
}

NSString *stringWithFileSystemRepresentation(const char *input)
{
    return [[NSFileManager defaultManager] stringWithFileSystemRepresentation:input length:strlen(input)];
}

uint16_t latestMinorVersionForMajorVersion(SUBinaryDeltaMajorVersion majorVersion)
{
    switch (majorVersion) {
        case SUBinaryDeltaMajorVersion1:
            return 2;
        case SUBinaryDeltaMajorVersion2:
            return 3;
        case SUBinaryDeltaMajorVersion3:
            return 0;
    }
    return 0;
}

NSString *temporaryFilename(NSString *base)
{
    NSString *template = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.XXXXXXXXXX", base]];
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:template.fileSystemRepresentation length:strlen(template.fileSystemRepresentation) + 1];

    char *buffer = data.mutableBytes;
    int fd = mkstemp(buffer);
    if (fd == -1) {
        perror("mkstemp");
        return nil;
    }

    if (close(fd) != 0) {
        perror("close");
        return nil;
    }

    return stringWithFileSystemRepresentation(buffer);
}

NSString *temporaryDirectory(NSString *base)
{
    NSString *template = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.XXXXXXXXXX", base]];
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:template.fileSystemRepresentation length:strlen(template.fileSystemRepresentation) + 1];

    char *buffer = data.mutableBytes;
    char *templateResult = mkdtemp(buffer);
    if (templateResult == NULL) {
        perror("mkdtemp");
        return nil;
    }

    return stringWithFileSystemRepresentation(templateResult);
}

static void _hashOfBuffer(unsigned char *hash, const char *buffer, ssize_t bufferLength)
{
    assert(bufferLength >= 0 && bufferLength <= UINT32_MAX);
    CC_SHA1_CTX hashContext;
    CC_SHA1_Init(&hashContext);
    CC_SHA1_Update(&hashContext, buffer, (CC_LONG)bufferLength);
    CC_SHA1_Final(hash, &hashContext);
}

static BOOL _hashOfFileContents(unsigned char *hash, FTSENT *ent)
{
    if (ent->fts_info == FTS_SL) {
        char linkDestination[MAXPATHLEN + 1];
        ssize_t linkDestinationLength = readlink(ent->fts_path, linkDestination, MAXPATHLEN);
        if (linkDestinationLength < 0) {
            perror("readlink");
            return NO;
        }

        _hashOfBuffer(hash, linkDestination, linkDestinationLength);
    } else if (ent->fts_info == FTS_F) {
        int fileDescriptor = open(ent->fts_path, O_RDONLY);
        if (fileDescriptor == -1) {
            perror("open");
            return NO;
        }

        ssize_t fileSize = ent->fts_statp->st_size;
        if (fileSize == 0) {
            _hashOfBuffer(hash, NULL, 0);
        } else {
            void *buffer = mmap(0, (size_t)fileSize, PROT_READ, MAP_FILE | MAP_PRIVATE, fileDescriptor, 0);
            if (buffer == (void *)-1) {
                close(fileDescriptor);
                perror("mmap");
                return NO;
            }

            _hashOfBuffer(hash, buffer, fileSize);
            munmap(buffer, (size_t)fileSize);
        }
        close(fileDescriptor);
    } else if (ent->fts_info == FTS_D) {
        memset(hash, 0xdd, CC_SHA1_DIGEST_LENGTH);
    } else {
        return NO;
    }
    return YES;
}

BOOL getRawHashOfTreeWithVersion(unsigned char *hashBuffer, NSString *path, uint16_t majorVersion)
{
    return getRawHashOfTreeAndFileTablesWithVersion(hashBuffer, path, majorVersion, nil, nil);
}

BOOL getRawHashOfTreeAndFileTablesWithVersion(unsigned char *hashBuffer, NSString *path, uint16_t __unused majorVersion, NSMutableDictionary<NSData *, NSMutableArray<NSString *> *> *hashToFileKeyDictionary, NSMutableDictionary<NSString *, NSData *> *fileKeyToHashDictionary)
{
    char pathBuffer[PATH_MAX] = { 0 };
    if (![path getFileSystemRepresentation:pathBuffer maxLength:sizeof(pathBuffer)]) {
        return NO;
    }

    char *const sourcePaths[] = { pathBuffer, 0 };
    FTS *fts = fts_open(sourcePaths, FTS_PHYSICAL | FTS_NOCHDIR, compareFiles);
    if (!fts) {
        perror("fts_open");
        return NO;
    }

    CC_SHA1_CTX hashContext;
    CC_SHA1_Init(&hashContext);

    // Ensure the path uses filesystem-specific Unicode normalization #1017
    NSString *normalizedPath = stringWithFileSystemRepresentation(pathBuffer);

    FTSENT *ent = 0;
    while ((ent = fts_read(fts))) {
        if (ent->fts_info != FTS_F && ent->fts_info != FTS_SL && ent->fts_info != FTS_D)
            continue;

        NSString *relativePath = pathRelativeToDirectory(normalizedPath, stringWithFileSystemRepresentation(ent->fts_path));
        if (relativePath.length == 0)
            continue;

        unsigned char fileHash[CC_SHA1_DIGEST_LENGTH];
        if (!_hashOfFileContents(fileHash, ent)) {
            return NO;
        }
        CC_SHA1_Update(&hashContext, fileHash, sizeof(fileHash));
        
        // For file hash tables we only track regular files
        if (ent->fts_info == FTS_F) {
            NSData *hashKey = [NSData dataWithBytes:fileHash length:sizeof(fileHash)];
            
            if (hashToFileKeyDictionary != nil) {
                if (hashToFileKeyDictionary[hashKey] == nil) {
                    hashToFileKeyDictionary[hashKey] = [NSMutableArray array];
                }
                [hashToFileKeyDictionary[hashKey] addObject:relativePath];
            }
            
            if (fileKeyToHashDictionary != nil) {
                fileKeyToHashDictionary[relativePath] = hashKey;
            }
        }

        const char *relativePathBytes = [relativePath fileSystemRepresentation];
        CC_SHA1_Update(&hashContext, relativePathBytes, (CC_LONG)strlen(relativePathBytes));

        uint16_t mode = ent->fts_statp->st_mode;
        // permission of symlinks is irrelevant and can't be changed.
        // hardcoding a value helps avoid differences between filesystems.
        if (ent->fts_info == FTS_SL) {
            mode = 0755;
        }
        uint16_t type = ent->fts_info;
        uint16_t permissions = mode & PERMISSION_FLAGS;

        CC_SHA1_Update(&hashContext, &type, sizeof(type));
        CC_SHA1_Update(&hashContext, &permissions, sizeof(permissions));
    }
    fts_close(fts);

    CC_SHA1_Final(hashBuffer, &hashContext);
    
    return YES;
}

void getRawHashFromDisplayHash(unsigned char *hash, NSString *hexHash)
{
    const char *hexString = hexHash.UTF8String;
    if (hexString == NULL) {
        return;
    }
    
    for (size_t blockIndex = 0; blockIndex < CC_SHA1_DIGEST_LENGTH; blockIndex++) {
        const char *currentBlock = hexString + blockIndex * 2;
        char convertedBlock[3] = {currentBlock[0], currentBlock[1], '\0'};
        hash[blockIndex] = (unsigned char)strtol(convertedBlock, NULL, 16);
    }
}

NSString *displayHashFromRawHash(const unsigned char *hash)
{
    char hexHash[CC_SHA1_DIGEST_LENGTH * 2 + 1] = {0};
    for (size_t i = 0; i < CC_SHA1_DIGEST_LENGTH; i++) {
        sprintf(hexHash + i * 2, "%02x", hash[i]);
    }
    return @(hexHash);
}

NSString *hashOfTreeWithVersion(NSString *path, uint16_t majorVersion)
{
    unsigned char hash[CC_SHA1_DIGEST_LENGTH];
    if (!getRawHashOfTreeWithVersion(hash, path, majorVersion)) {
        return nil;
    }
    return displayHashFromRawHash(hash);
}

extern NSString *hashOfTree(NSString *path)
{
    return hashOfTreeWithVersion(path, SUBinaryDeltaMajorVersionLatest);
}

BOOL removeTree(NSString *path)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    // Don't use fileExistsForPath: because it will try to follow symbolic links
    if (![fileManager attributesOfItemAtPath:path error:nil]) {
        return YES;
    }
    return [fileManager removeItemAtPath:path error:nil];
}

BOOL copyTree(NSString *source, NSString *dest)
{
    // SUFileManager will be more reliable for copying items especially across network mounts
    return [[[SUFileManager alloc] init] copyItemAtURL:[NSURL fileURLWithPath:source] toURL:[NSURL fileURLWithPath:dest] error:NULL];
}

BOOL modifyPermissions(NSString *path, mode_t desiredPermissions)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *attributes = [fileManager attributesOfItemAtPath:path error:nil];
    if (!attributes) {
        return NO;
    }
    NSNumber *permissions = [attributes objectForKey:NSFilePosixPermissions];
    if (!permissions) {
        return NO;
    }
    mode_t newMode = ([permissions unsignedShortValue] & ~PERMISSION_FLAGS) | desiredPermissions;
    int (*changeModeFunc)(const char *, mode_t) = [(NSString *)[attributes objectForKey:NSFileType] isEqualToString:NSFileTypeSymbolicLink] ? lchmod : chmod;
    if (changeModeFunc([path fileSystemRepresentation], newMode) != 0) {
        return NO;
    }
    return YES;
}
