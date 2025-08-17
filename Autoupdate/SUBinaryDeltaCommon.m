//
//  SUBinaryDeltaCommon.m
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-01.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#include "SUBinaryDeltaCommon.h"
#include <CommonCrypto/CommonDigest.h>
#include <zlib.h> // for crc32()
#include <Foundation/Foundation.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <xlocale.h>

#include "AppKitPrevention.h"

// Note: the framework bundle version must be bumped, and generate_appcast must be updated to compare it,
// when we add/change new major versions and defaults. Unit tests need to be updated to use new versions too.
SUBinaryDeltaMajorVersion SUBinaryDeltaMajorVersionDefault = SUBinaryDeltaMajorVersion4;
SUBinaryDeltaMajorVersion SUBinaryDeltaMajorVersionLatest = SUBinaryDeltaMajorVersion4;
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
    return strcoll_l((*a)->fts_name, (*b)->fts_name, _c_locale);
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
            return 5;
        case SUBinaryDeltaMajorVersion3:
            return 3;
        case SUBinaryDeltaMajorVersion4:
            return 2;
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

static void sha1HashOfBuffer(unsigned char *hash, const char *buffer, ssize_t bufferLength)
{
    assert(bufferLength >= 0 && bufferLength <= UINT32_MAX);
    CC_SHA1_CTX hashContext;
    CC_SHA1_Init(&hashContext);
    CC_SHA1_Update(&hashContext, buffer, (CC_LONG)bufferLength);
    CC_SHA1_Final(hash, &hashContext);
}

static BOOL crc32HashOfFileContents(uLong *outChecksum, FTSENT *ent, void *tempBuffer, size_t tempBufferSize)
{
    uLong checksum = *outChecksum;
    
    if (ent->fts_info == FTS_SL) {
        char linkDestination[MAXPATHLEN + 1];
        ssize_t linkDestinationLength = readlink(ent->fts_path, linkDestination, MAXPATHLEN);
        if (linkDestinationLength < 0) {
            perror("readlink");
            return NO;
        }
        
        checksum = crc32(checksum, (const void *)linkDestination, (unsigned int)linkDestinationLength);
    } else if (ent->fts_info == FTS_F) {
        ssize_t fileSize = ent->fts_statp->st_size;
        
        uint64_t encodedFileSize = (uint64_t)fileSize;
        checksum = crc32(checksum, (const void *)&encodedFileSize, sizeof(encodedFileSize));
        
        if (fileSize > 0) {
            FILE *file = fopen(ent->fts_path, "rb");
            if (file == NULL) {
                perror("fopen");
                return NO;
            }
            
            size_t bytesLeft = (size_t)fileSize;
            while (bytesLeft > 0) {
                size_t bytesToConsume = (bytesLeft >= tempBufferSize) ? tempBufferSize : bytesLeft;
                
                if (fread(tempBuffer, bytesToConsume, 1, file) < 1) {
                    perror("fread");
                    fclose(file);
                    return NO;
                }
                
                checksum = crc32(checksum, tempBuffer, (uInt)bytesToConsume);
                
                bytesLeft -= bytesToConsume;
            }
            
            fclose(file);
        }
    } else {
        return NO;
    }
    
    *outChecksum = checksum;
    
    return YES;
}

static BOOL sha1HashOfFileContents(unsigned char *hash, FTSENT *ent, void *tempBuffer, size_t tempBufferSize)
{
    if (ent->fts_info == FTS_SL) {
        char linkDestination[MAXPATHLEN + 1];
        ssize_t linkDestinationLength = readlink(ent->fts_path, linkDestination, MAXPATHLEN);
        if (linkDestinationLength < 0) {
            perror("readlink");
            return NO;
        }

        sha1HashOfBuffer(hash, linkDestination, linkDestinationLength);
    } else if (ent->fts_info == FTS_F) {
        ssize_t fileSize = ent->fts_statp->st_size;
        if (fileSize <= 0) {
            sha1HashOfBuffer(hash, NULL, 0);
        } else {
            FILE *file = fopen(ent->fts_path, "rb");
            if (file == NULL) {
                perror("fopen");
                return NO;
            }
            
            CC_SHA1_CTX hashContext;
            CC_SHA1_Init(&hashContext);
            
            size_t bytesLeft = (size_t)fileSize;
            while (bytesLeft > 0) {
                size_t bytesToConsume = (bytesLeft >= tempBufferSize) ? tempBufferSize : bytesLeft;
                
                if (fread(tempBuffer, bytesToConsume, 1, file) < 1) {
                    perror("fread");
                    fclose(file);
                    return NO;
                }
                
                CC_SHA1_Update(&hashContext, tempBuffer, (CC_LONG)bytesToConsume);
                bytesLeft -= bytesToConsume;
            }
            
            CC_SHA1_Final(hash, &hashContext);
            
            fclose(file);
        }
    } else if (ent->fts_info == FTS_D) {
        memset(hash, 0xdd, CC_SHA1_DIGEST_LENGTH);
    } else {
        return NO;
    }
    return YES;
}

BOOL getRawHashOfTreeWithVersion(void *hashBuffer, NSString *path, uint16_t majorVersion)
{
    return getRawHashOfTreeAndFileTablesWithVersion(hashBuffer, path, majorVersion, nil, nil);
}

BOOL getRawHashOfTreeAndFileTablesWithVersion(void *hashBuffer, NSString *path, uint16_t majorVersion, NSMutableDictionary<NSData *, NSMutableArray<NSString *> *> *hashToFileKeyDictionary, NSMutableDictionary<NSString *, NSData *> *fileKeyToHashDictionary)
{
    char pathBuffer[PATH_MAX] = { 0 };
    if (![path getFileSystemRepresentation:pathBuffer maxLength:sizeof(pathBuffer)]) {
        return NO;
    }

    const size_t tempBufferSize = 16384;
    void *tempBuffer = calloc(1, tempBufferSize);
    if (tempBuffer == NULL) {
        perror("calloc");
        return NO;
    }
    
    char *const sourcePaths[] = { pathBuffer, 0 };
    FTS *fts = fts_open(sourcePaths, FTS_PHYSICAL | FTS_NOCHDIR, compareFiles);
    if (!fts) {
        perror("fts_open");
        free(tempBuffer);
        return NO;
    }

    CC_SHA1_CTX hashContext;
    const uLong initialCrc32Value = crc32(0L, Z_NULL, 0);
    uLong crc32ChecksumValue = initialCrc32Value;
    
    if (majorVersion < SUBinaryDeltaMajorVersion4) {
        CC_SHA1_Init(&hashContext);
    }

    // Ensure the path uses filesystem-specific Unicode normalization #1017
    NSString *normalizedPath = stringWithFileSystemRepresentation(pathBuffer);

    FTSENT *ent = 0;
    while ((ent = fts_read(fts))) {
        if (ent->fts_info != FTS_F && ent->fts_info != FTS_SL && ent->fts_info != FTS_D)
            continue;

        NSString *relativePath = pathRelativeToDirectory(normalizedPath, stringWithFileSystemRepresentation(ent->fts_path));
        
        // Ignore icon resource fork data
        if (relativePath.length == 0 || [relativePath isEqualToString:CUSTOM_ICON_PATH]) {
            continue;
        }

        NSData *fileHashKey;
        if (majorVersion >= SUBinaryDeltaMajorVersion4) {
            if (ent->fts_info == FTS_D) {
                // No need to hash any further values for directories
                // We hash relative file path and file type later
                fileHashKey = nil;
            } else {
                uLong fileContentsChecksum = initialCrc32Value;
                if (!crc32HashOfFileContents(&fileContentsChecksum, ent, tempBuffer, tempBufferSize)) {
                    fts_close(fts);
                    free(tempBuffer);
                    return NO;
                }
                
                uint64_t encodedFileContentsChecksum = fileContentsChecksum;
                
                crc32ChecksumValue = crc32(crc32ChecksumValue, (const void *)&encodedFileContentsChecksum, sizeof(encodedFileContentsChecksum));
                
                if (ent->fts_info == FTS_F) {
                    fileHashKey = [NSData dataWithBytes:&encodedFileContentsChecksum length:sizeof(encodedFileContentsChecksum)];
                } else {
                    fileHashKey = nil;
                }
            }
        } else {
            unsigned char fileHash[CC_SHA1_DIGEST_LENGTH];
            if (!sha1HashOfFileContents(fileHash, ent, tempBuffer, tempBufferSize)) {
                fts_close(fts);
                free(tempBuffer);
                return NO;
            }
            CC_SHA1_Update(&hashContext, fileHash, sizeof(fileHash));
            
            if (ent->fts_info == FTS_F) {
                fileHashKey = [NSData dataWithBytes:fileHash length:sizeof(fileHash)];
            } else {
                fileHashKey = nil;
            }
        }
        
        // For file hash tables we only track regular files
        if (fileHashKey != nil) {
            if (hashToFileKeyDictionary != nil) {
                if (hashToFileKeyDictionary[fileHashKey] == nil) {
                    hashToFileKeyDictionary[fileHashKey] = [NSMutableArray array];
                }
                [hashToFileKeyDictionary[fileHashKey] addObject:relativePath];
            }
            
            if (fileKeyToHashDictionary != nil) {
                fileKeyToHashDictionary[relativePath] = fileHashKey;
            }
        }

        const char *relativePathBytes = [relativePath fileSystemRepresentation];
        
        if (majorVersion >= SUBinaryDeltaMajorVersion4) {
            crc32ChecksumValue = crc32(crc32ChecksumValue, (const void *)relativePathBytes, (uInt)strlen(relativePathBytes));
        } else {
            CC_SHA1_Update(&hashContext, relativePathBytes, (CC_LONG)strlen(relativePathBytes));
        }

        uint16_t mode = ent->fts_statp->st_mode;
        uint16_t type = ent->fts_info;
        uint16_t permissions = mode & PERMISSION_FLAGS;
        
        // permission of symlinks are 0777 on some linux file systems and can't be changed,
        // differing from the 0755 macOS default.
        // hardcoding a value helps avoid differences between filesystems.
        uint16_t hashedPermissions = (ent->fts_info == FTS_SL) ? VALID_SYMBOLIC_LINK_PERMISSIONS : permissions;

        if (majorVersion >= SUBinaryDeltaMajorVersion4) {
            crc32ChecksumValue = crc32(crc32ChecksumValue, (const void *)&type, sizeof(type));
            crc32ChecksumValue = crc32(crc32ChecksumValue, (const void *)&hashedPermissions, sizeof(hashedPermissions));
        } else {
            CC_SHA1_Update(&hashContext, &type, sizeof(type));
            CC_SHA1_Update(&hashContext, &hashedPermissions, sizeof(hashedPermissions));
        }
    }
    
    free(tempBuffer);
    
    fts_close(fts);

    if (majorVersion >= SUBinaryDeltaMajorVersion4) {
        uint64_t encodedCrc32ChecksumValue = crc32ChecksumValue;
        memset(hashBuffer, 0, BINARY_DELTA_HASH_LENGTH);
        memcpy(hashBuffer, &encodedCrc32ChecksumValue, sizeof(encodedCrc32ChecksumValue));
    } else {
        CC_SHA1_Final(hashBuffer, &hashContext);
    }
    
    return YES;
}

void getRawHashFromDisplayHash(unsigned char *hash, NSString *hexHash)
{
    const char *hexString = hexHash.UTF8String;
    if (hexString == NULL) {
        return;
    }
    
    for (size_t blockIndex = 0; blockIndex < BINARY_DELTA_HASH_LENGTH; blockIndex++) {
        const char *currentBlock = hexString + blockIndex * 2;
        char convertedBlock[3] = {currentBlock[0], currentBlock[1], '\0'};
        hash[blockIndex] = (unsigned char)strtol(convertedBlock, NULL, 16);
    }
}

NSString *displayHashFromRawHash(const unsigned char *hash)
{
    char hexHash[BINARY_DELTA_HASH_LENGTH * 2 + 1] = {0};
    for (size_t i = 0; i < BINARY_DELTA_HASH_LENGTH; i++) {
        snprintf(hexHash + i * 2, 3, "%02x", hash[i]);
    }
    return @(hexHash);
}

NSString *hashOfTreeWithVersion(NSString *path, uint16_t majorVersion)
{
    unsigned char hash[BINARY_DELTA_HASH_LENGTH] = {0};
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

BOOL copyTree(NSFileManager *fileManager, NSString *source, NSString *dest)
{
    return [fileManager copyItemAtURL:[NSURL fileURLWithPath:source] toURL:[NSURL fileURLWithPath:dest] error:NULL];
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
