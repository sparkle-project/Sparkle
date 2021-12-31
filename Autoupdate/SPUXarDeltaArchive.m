//
//  SPUXarDeltaArchive.m
//  Autoupdate
//
//  Created by Mayur Pawashe on 12/28/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

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

@interface SPUXarDeltaArchive ()

@property (nonatomic) xar_t x;
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSValue *> *fileTable;

@end

@implementation SPUXarDeltaArchive

@synthesize x = _x;
@synthesize fileTable = _fileTable;

- (nullable instancetype)initWithPatchFileForWriting:(NSString *)patchFile compression:(SPUDeltaCompressionMode)compression compressionLevel:(int32_t)compressionLevel
{
    self = [super init];
    if (self != nil) {
        _x = xar_open(patchFile.fileSystemRepresentation, WRITE);
        if (_x == NULL) {
            return nil;
        }
        
        _fileTable = [NSMutableDictionary dictionary];
        
        switch (compression) {
            case SPUDeltaCompressionModeNone:
                break;
            case SPUDeltaCompressionModeBzip2: {
                xar_opt_set(_x, XAR_OPT_COMPRESSION, "bzip2");
                
                char buffer[256] = {0};
                snprintf(buffer, sizeof(buffer) - 1, "%d", compressionLevel);
                xar_opt_set(_x, XAR_OPT_COMPRESSIONARG, buffer);
                
                break;
            }
        }
    }
    return self;
}

- (nullable instancetype)initWithPatchFileForReading:(NSString *)patchFile
{
    self = [super init];
    if (self != nil) {
        _x = xar_open(patchFile.fileSystemRepresentation, READ);
        if (_x == NULL) {
            return nil;
        }
    }
    return self;
}

- (void)dealloc
{
    [self close];
}

- (void)close
{
    if (self.x != NULL) {
        xar_close(self.x);
        self.x = NULL;
    }
}

- (NSError * _Nullable)error
{
    return nil;
}

// This indicates if safe extraction is available at compile time (SDK), but not if it's available at runtime.
+ (BOOL)maySupportSafeExtraction
{
    return HAS_XAR_GET_SAFE_PATH;
}

- (nullable SPUDeltaArchiveHeader *)readHeader
{
    uint16_t majorDiffVersion = FIRST_DELTA_DIFF_MAJOR_VERSION;
    uint16_t minorDiffVersion = 0;
    NSString *expectedBeforeHash = nil;
    NSString *expectedAfterHash = nil;

    xar_subdoc_t subdoc;
    for (subdoc = xar_subdoc_first(self.x); subdoc; subdoc = xar_subdoc_next(subdoc)) {
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
    
    unsigned char rawExpectedBeforeHash[CC_SHA1_DIGEST_LENGTH] = {0};
    getRawHashFromDisplayHash(rawExpectedBeforeHash, expectedBeforeHash);
    
    unsigned char rawExpectedAfterHash[CC_SHA1_DIGEST_LENGTH] = {0};
    getRawHashFromDisplayHash(rawExpectedAfterHash, expectedAfterHash);
    
    return [[SPUDeltaArchiveHeader alloc] initWithMajorVersion:majorDiffVersion minorVersion:minorDiffVersion beforeTreeHash:rawExpectedBeforeHash afterTreeHash:rawExpectedAfterHash];
}

- (void)writeHeader:(SPUDeltaArchiveHeader *)header
{
    xar_subdoc_t attributes = xar_subdoc_new(self.x, BINARY_DELTA_ATTRIBUTES_KEY);
    
    xar_subdoc_prop_set(attributes, MAJOR_DIFF_VERSION_KEY, [[NSString stringWithFormat:@"%u", header.majorVersion] UTF8String]);
    xar_subdoc_prop_set(attributes, MINOR_DIFF_VERSION_KEY, [[NSString stringWithFormat:@"%u", header.minorVersion] UTF8String]);
    
    xar_subdoc_prop_set(attributes, BEFORE_TREE_SHA1_KEY, [displayHashFromRawHash(header.beforeTreeHash) UTF8String]);
    xar_subdoc_prop_set(attributes, AFTER_TREE_SHA1_KEY, [displayHashFromRawHash(header.afterTreeHash) UTF8String]);
}

static xar_file_t _xarAddFile(NSMutableDictionary<NSString *, NSValue *> *fileTable, xar_t x, NSString *relativePath, NSString *filePath)
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
    // mis-ordering bugs
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
    NSString *relativeFilePath = item.relativeFilePath;
    NSString *filePath = item.physicalFilePath;
    SPUDeltaItemCommands commands = item.commands;
    uint16_t permissions = item.permissions;
    
    xar_file_t newFile = _xarAddFile(self.fileTable, self.x, relativeFilePath, filePath);
    assert(newFile != NULL);
    
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
        xar_prop_set(newFile, MODIFY_PERMISSIONS_KEY, [NSString stringWithFormat:@"%u", permissions].UTF8String);
    }
}

- (void)finishEncodingItems
{
    // Items are already encoded when they are extracted prior
}

- (void)enumerateItems:(void (^)(SPUDeltaArchiveItem *, BOOL *))itemHandler
{
    BOOL exitedEarly = NO;
    xar_iter_t iter = xar_iter_new();
    for (xar_file_t file = xar_file_first(self.x, iter); file; file = xar_file_next(iter)) {
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
        
        NSString *relativePath = @(pathCString);
        
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
        
        uint16_t permissions = 0;
        {
            const char *value = NULL;
            if (xar_prop_get(file, MODIFY_PERMISSIONS_KEY, &value) == 0) {
                commands |= SPUDeltaItemCommandModifyPermissions;
                permissions = (uint16_t)[@(value) intValue];
            }
        }
        
        SPUDeltaArchiveItem *item = [[SPUDeltaArchiveItem alloc] initWithRelativeFilePath:relativePath commands:commands permissions:permissions];
        item.context = file;
        
        itemHandler(item, &exitedEarly);
        if (exitedEarly) {
            break;
        }
    }
    
    xar_iter_free(iter);
}

- (BOOL)extractItem:(SPUDeltaArchiveItem *)item
{
    assert(item.physicalFilePath != nil);
    assert(item.context != NULL);
    
    xar_file_t file = item.context;
    return (xar_extract_tofile(self.x, file, item.physicalFilePath.fileSystemRepresentation) == 0);
}

@end
