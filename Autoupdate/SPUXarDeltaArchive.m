//
//  SPUXarDeltaArchive.m
//  Autoupdate
//
//  Created by Mayur Pawashe on 12/28/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_LEGACY_DELTA_SUPPORT

#import "SPUXarDeltaArchive.h"
#include <xar/xar.h>
#include "SUBinaryDeltaCommon.h"
#import <Availability.h>
#import <CommonCrypto/CommonDigest.h>


#include "AppKitPrevention.h"

#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 120000
    #define HAS_XAR_GET_SAFE_PATH 1
#else
    #define HAS_XAR_GET_SAFE_PATH 0
#endif

#if HAS_XAR_GET_SAFE_PATH
// This is preferred over xar_get_path (which is deprecated) when it's available
// Don't use OS availability for this API
extern char *xar_get_safe_path(xar_file_t f) __attribute__((weak_import));
#endif

// Xar attribute keys
#define BINARY_DELTA_ATTRIBUTES_KEY "binary-delta-attributes"
#define MAJOR_DIFF_VERSION_KEY "major-version"
#define MINOR_DIFF_VERSION_KEY "minor-version"
#define BEFORE_TREE_SHA1_KEY "before-tree-sha1"
#define AFTER_TREE_SHA1_KEY "after-tree-sha1"
#define DELETE_KEY "delete"
#define EXTRACT_KEY "extract"
#define BINARY_DELTA_KEY "binary-delta"
#define MODIFY_PERMISSIONS_KEY "mod-permissions"

// Errors
#define SPARKLE_DELTA_XAR_ARCHIVE_ERROR_DOMAIN @"Sparkle XAR Archive"
#define SPARKLE_DELTA_XAR_ARCHIVE_ERROR_CODE_OPEN_FAILURE 1
#define SPARKLE_DELTA_XAR_ARCHIVE_ERROR_CODE_ADD_FAILURE 2
#define SPARKLE_DELTA_XAR_ARCHIVE_ERROR_CODE_EXTRACT_FAILURE 3
#define SPARKLE_DELTA_XAR_ARCHIVE_ERROR_CODE_UNSUPPORTED_COMPRESSION_FAILURE 4

@implementation SPUXarDeltaArchive
{
    NSMutableDictionary<NSString *, NSValue *> *_fileTable;
    NSString *_patchFile;
    
    xar_t _x;
    int32_t _xarMode;
}

@synthesize error = _error;

- (instancetype)initWithPatchFileForWriting:(NSString *)patchFile
{
    self = [super init];
    if (self != nil) {
        _patchFile = [patchFile copy];
        _xarMode = WRITE;
        _fileTable = [NSMutableDictionary dictionary];
    }
    return self;
}

- (instancetype)initWithPatchFileForReading:(NSString *)patchFile
{
    self = [super init];
    if (self != nil) {
        _patchFile = [patchFile copy];
        _xarMode = READ;
    }
    return self;
}

- (void)dealloc
{
    [self close];
}

- (void)close
{
    if (_x != NULL) {
        xar_close(_x);
        _x = NULL;
    }
}

// This indicates if safe extraction is available at compile time (SDK), but not if it's available at runtime.
+ (BOOL)maySupportSafeExtraction
{
    return HAS_XAR_GET_SAFE_PATH;
}

- (nullable SPUDeltaArchiveHeader *)readHeader
{
    NSString *patchFile = _patchFile;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // Sparkle's XAR delta archives have been superseded by Sparkle's own format
    xar_t x = xar_open(patchFile.fileSystemRepresentation, READ);
#pragma clang diagnostic pop
    if (x == NULL) {
        _error = [NSError errorWithDomain:SPARKLE_DELTA_XAR_ARCHIVE_ERROR_DOMAIN code:SPARKLE_DELTA_XAR_ARCHIVE_ERROR_CODE_OPEN_FAILURE userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to xar_open() file for reading: %@", patchFile] }];
        return nil;
    }
    
    _x = x;
    
    uint16_t majorDiffVersion = SUBinaryDeltaMajorVersionFirst;
    uint16_t minorDiffVersion = 0;
    NSString *expectedBeforeHash = nil;
    NSString *expectedAfterHash = nil;

    xar_subdoc_t subdoc;
    for (subdoc = xar_subdoc_first(_x); subdoc; subdoc = xar_subdoc_next(subdoc)) {
        if (strcmp(xar_subdoc_name(subdoc), BINARY_DELTA_ATTRIBUTES_KEY) == 0) {
            {
                // available in version 2.0 or later
                const char *value = NULL;
                xar_subdoc_prop_get(subdoc, MAJOR_DIFF_VERSION_KEY, &value);
                if (value != NULL) {
                    majorDiffVersion = (uint16_t)[@(value) intValue];
                }
            }

            {
                // available in version 2.0 or later
                const char *value = NULL;
                xar_subdoc_prop_get(subdoc, MINOR_DIFF_VERSION_KEY, &value);
                if (value != NULL) {
                    minorDiffVersion = (uint16_t)[@(value) intValue];
                }
            }
            
            // available in version 2.0 or later
            {
                const char *value = NULL;
                xar_subdoc_prop_get(subdoc, BEFORE_TREE_SHA1_KEY, &value);
                if (value != NULL) {
                    expectedBeforeHash = @(value);
                }
            }

            // available in version 2.0 or later
            {
                const char *value = NULL;
                xar_subdoc_prop_get(subdoc, AFTER_TREE_SHA1_KEY, &value);
                if (value != NULL) {
                    expectedAfterHash = @(value);
                }
            }
        }
    }
    
    unsigned char rawExpectedBeforeHash[BINARY_DELTA_HASH_LENGTH] = {0};
    getRawHashFromDisplayHash(rawExpectedBeforeHash, expectedBeforeHash);
    
    unsigned char rawExpectedAfterHash[BINARY_DELTA_HASH_LENGTH] = {0};
    getRawHashFromDisplayHash(rawExpectedAfterHash, expectedAfterHash);
    
    // I wasn't able to figure out how to retrieve the compression options from xar,
    // so we will use default flags to indicate the info isn't available
    return [[SPUDeltaArchiveHeader alloc] initWithCompression:SPUDeltaCompressionModeDefault compressionLevel:0 fileSystemCompression:false majorVersion:majorDiffVersion minorVersion:minorDiffVersion beforeTreeHash:rawExpectedBeforeHash afterTreeHash:rawExpectedAfterHash bundleCreationDate:nil];
}

- (void)writeHeader:(SPUDeltaArchiveHeader *)header
{
    NSString *patchFile = _patchFile;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // Sparkle's XAR delta archives have been superseded by Sparkle's own format
    xar_t x = xar_open(patchFile.fileSystemRepresentation, WRITE);
#pragma clang diagnostic pop
    if (x == NULL) {
        _error = [NSError errorWithDomain:SPARKLE_DELTA_XAR_ARCHIVE_ERROR_DOMAIN code:SPARKLE_DELTA_XAR_ARCHIVE_ERROR_CODE_OPEN_FAILURE userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to xar_open() file for writing: %@", patchFile] }];
        return;
    }
    
    _x = x;
    
    SPUDeltaCompressionMode compression = (header.compression == SPUDeltaCompressionModeDefault ? SPUDeltaCompressionModeBzip2 : header.compression);
    
    uint8_t compressionLevel;
    // Only 1 - 9 are valid, 0 is special case to use default level 9
    if (header.compressionLevel <= 0 || header.compressionLevel > 9) {
        compressionLevel = 9;
    } else {
        compressionLevel = header.compressionLevel;
    }
    
    switch (compression) {
        case SPUDeltaCompressionModeNone:
            xar_opt_set(x, XAR_OPT_COMPRESSION, XAR_OPT_VAL_NONE);
            break;
        case SPUDeltaCompressionModeBzip2: {
            xar_opt_set(x, XAR_OPT_COMPRESSION, "bzip2");
            
            char buffer[256] = {0};
            snprintf(buffer, sizeof(buffer) - 1, "%d", compressionLevel);
            xar_opt_set(x, XAR_OPT_COMPRESSIONARG, buffer);
            
            break;
        }
        case SPUDeltaCompressionModeLZMA:
        case SPUDeltaCompressionModeLZFSE:
        case SPUDeltaCompressionModeLZ4:
        case SPUDeltaCompressionModeZLIB: {
            _error = [NSError errorWithDomain:SPARKLE_DELTA_XAR_ARCHIVE_ERROR_DOMAIN code:SPARKLE_DELTA_XAR_ARCHIVE_ERROR_CODE_UNSUPPORTED_COMPRESSION_FAILURE userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Version 2 patches only support bzip2 compression."] }];
            
            return;
        }
    }
    
    xar_subdoc_t attributes = xar_subdoc_new(x, BINARY_DELTA_ATTRIBUTES_KEY);
    
    xar_subdoc_prop_set(attributes, MAJOR_DIFF_VERSION_KEY, [[NSString stringWithFormat:@"%u", header.majorVersion] UTF8String]);
    xar_subdoc_prop_set(attributes, MINOR_DIFF_VERSION_KEY, [[NSString stringWithFormat:@"%u", header.minorVersion] UTF8String]);
    
    xar_subdoc_prop_set(attributes, BEFORE_TREE_SHA1_KEY, [displayHashFromRawHash(header.beforeTreeHash) UTF8String]);
    xar_subdoc_prop_set(attributes, AFTER_TREE_SHA1_KEY, [displayHashFromRawHash(header.afterTreeHash) UTF8String]);
}

static xar_file_t xarAddFile(NSMutableDictionary<NSString *, NSValue *> *fileTable, xar_t x, NSString *relativePath, NSString *filePath)
{
    NSArray<NSString *> *rootRelativePathComponents = relativePath.pathComponents;
    // Relative path must at least have starting "/" component and one more path component
    if (rootRelativePathComponents.count < 2) {
        return NULL;
    }
    
    NSArray<NSString *> *relativePathComponents = [rootRelativePathComponents subarrayWithRange:NSMakeRange(1, rootRelativePathComponents.count - 1)];
    
    NSUInteger relativePathComponentsCount = relativePathComponents.count;
    
    // Build parent files as needed until we get to our final file we want to add
    // So if we get "Contents/Resources/foo.txt", we will first add "Contents" parent,
    // then "Resources" parent, then "foo.txt" as the final entry we want to add
    // We store every file we add into a fileTable for easy referencing
    // Note if a diff has Contents/Resources/foo/ and Contents/Resources/foo/bar.txt,
    // due to sorting order we will add the foo directory first and won't end up with
    // misordering bugs
    xar_file_t lastParent = NULL;
    for (NSUInteger componentIndex = 0; componentIndex < relativePathComponentsCount; componentIndex++) {
        NSArray<NSString *> *subpathComponents = [relativePathComponents subarrayWithRange:NSMakeRange(0, componentIndex + 1)];
        NSString *subpathKey = [subpathComponents componentsJoinedByString:@"/"];
        
        xar_file_t cachedFile = [fileTable[subpathKey] pointerValue];
        if (cachedFile != NULL) {
            lastParent = cachedFile;
        } else {
            xar_file_t newParent;
            
            BOOL atLastIndex = (componentIndex == relativePathComponentsCount - 1);
            
            NSString *lastPathComponent = subpathComponents.lastObject;
            if (atLastIndex && filePath != nil) {
                newParent = xar_add_frompath(x, lastParent, lastPathComponent.fileSystemRepresentation, filePath.fileSystemRepresentation);
            } else {
                newParent = xar_add_frombuffer(x, lastParent, lastPathComponent.fileSystemRepresentation, "", 1);
            }
            
            lastParent = newParent;
            fileTable[subpathKey] = [NSValue valueWithPointer:newParent];
        }
    }
    return lastParent;
}

- (void)addItem:(SPUDeltaArchiveItem *)item
{
    if (_error != nil) {
        return;
    }
    
    NSString *relativeFilePath = item.relativeFilePath;
    NSString *filePath = item.itemFilePath;
    SPUDeltaItemCommands commands = item.commands;
    uint16_t mode = item.mode;
    
    xar_file_t newFile = xarAddFile(_fileTable, _x, relativeFilePath, filePath);
    if (newFile == NULL) {
        _error = [NSError errorWithDomain:SPARKLE_DELTA_XAR_ARCHIVE_ERROR_DOMAIN code:SPARKLE_DELTA_XAR_ARCHIVE_ERROR_CODE_ADD_FAILURE userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to add xar file entry: %@", relativeFilePath] }];
        return;
    }
    
    if ((commands & SPUDeltaItemCommandDelete) != 0) {
        xar_prop_set(newFile, DELETE_KEY, "true");
    }
    
    if ((commands & SPUDeltaItemCommandExtract) != 0) {
        xar_prop_set(newFile, EXTRACT_KEY, "true");
    }
    
    if ((commands & SPUDeltaItemCommandBinaryDiff) != 0) {
        xar_prop_set(newFile, BINARY_DELTA_KEY, "true");
    }
    
    if ((commands & SPUDeltaItemCommandModifyPermissions) != 0) {
        xar_prop_set(newFile, MODIFY_PERMISSIONS_KEY, [NSString stringWithFormat:@"%u", mode].UTF8String);
    }
}

- (void)finishEncodingItems
{
    // Items are already encoded when they are extracted prior
}

- (void)enumerateItems:(void (^)(SPUDeltaArchiveItem *, BOOL *))itemHandler
{
    if (_error != nil) {
        return;
    }
    
    BOOL exitedEarly = NO;
    xar_iter_t iter = xar_iter_new();
    for (xar_file_t file = xar_file_first(_x, iter); file; file = xar_file_next(iter)) {
        char *pathCString;
#if HAS_XAR_GET_SAFE_PATH
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
        if (xar_get_safe_path != NULL) {
            pathCString = xar_get_safe_path(file);
        }
#pragma clang diagnostic pop
        else
#endif
        {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            pathCString = xar_get_path(file);
#pragma clang diagnostic pop
        }
        
        if (pathCString == NULL) {
            continue;
        }
        
        NSString *relativePath = [[NSString alloc] initWithBytesNoCopy:pathCString length:strlen(pathCString) encoding:NSUTF8StringEncoding freeWhenDone:YES];
        if (relativePath == nil) {
            free(pathCString);
            continue;
        }
        
        SPUDeltaItemCommands commands = 0;
        {
            const char *value = NULL;
            if (xar_prop_get(file, DELETE_KEY, &value) == 0) {
                commands |= SPUDeltaItemCommandDelete;
            }
        }
        {
            const char *value = NULL;
            if (xar_prop_get(file, BINARY_DELTA_KEY, &value) == 0) {
                commands |= SPUDeltaItemCommandBinaryDiff;
            }
        }
        {
            const char *value = NULL;
            if (xar_prop_get(file, EXTRACT_KEY, &value) == 0) {
                commands |= SPUDeltaItemCommandExtract;
            }
        }
        
        uint16_t mode = 0;
        {
            const char *value = NULL;
            if (xar_prop_get(file, MODIFY_PERMISSIONS_KEY, &value) == 0) {
                commands |= SPUDeltaItemCommandModifyPermissions;
                mode = (uint16_t)[@(value) intValue];
            }
        }
        
        SPUDeltaArchiveItem *item = [[SPUDeltaArchiveItem alloc] initWithRelativeFilePath:relativePath commands:commands mode:mode];
        item.xarContext = file;
        
        itemHandler(item, &exitedEarly);
        if (exitedEarly) {
            break;
        }
    }
    
    xar_iter_free(iter);
}

- (BOOL)extractItem:(SPUDeltaArchiveItem *)item
{
    if (_error != nil) {
        return NO;
    }
    
    assert(item.itemFilePath != nil);
    assert(item.xarContext != NULL);
    
    xar_file_t file = item.xarContext;
    if (xar_extract_tofile(_x, file, item.itemFilePath.fileSystemRepresentation) != 0) {
        _error = [NSError errorWithDomain:SPARKLE_DELTA_XAR_ARCHIVE_ERROR_DOMAIN code:SPARKLE_DELTA_XAR_ARCHIVE_ERROR_CODE_EXTRACT_FAILURE userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to extract xar file entry to %@", item.itemFilePath] }];
        return NO;
    }
    
    return YES;
}

@end

#endif
