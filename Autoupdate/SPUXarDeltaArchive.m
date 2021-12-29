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

#include "AppKitPrevention.h"

@interface SPUXarDeltaArchive ()

@property (nonatomic) xar_t x;
@property (nonatomic, readonly) NSMutableDictionary<NSString *, NSValue *> *fileTable;

@end

@implementation SPUXarDeltaArchive

@synthesize x = _x;
@synthesize fileTable = _fileTable;

+ (BOOL)getMajorDeltaVersion:(uint16_t *)outMajorDiffVersion minorDeltaVersion:(uint16_t *)outMinorDiffVersion fromPatchFile:(NSString *)patchFile
{
    xar_t x = xar_open([patchFile fileSystemRepresentation], READ);
    if (x == NULL) {
        return NO;
    }

    uint16_t majorDiffVersion = FIRST_DELTA_DIFF_MAJOR_VERSION;
    uint16_t minorDiffVersion = 0;

    xar_subdoc_t subdoc;
    for (subdoc = xar_subdoc_first(x); subdoc; subdoc = xar_subdoc_next(subdoc)) {
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
        }
    }
    
    if (outMajorDiffVersion != NULL) {
        *outMajorDiffVersion = majorDiffVersion;
    }
    
    if (outMinorDiffVersion != NULL) {
        *outMinorDiffVersion = minorDiffVersion;
    }
    
    xar_close(x);
    return YES;
}

- (nullable instancetype)initWithPatchFileForWriting:(NSString *)patchFile
{
    self = [super init];
    if (self != nil) {
        _x = xar_open(patchFile.fileSystemRepresentation, WRITE);
        if (_x == NULL) {
            return nil;
        }
        
        _fileTable = [NSMutableDictionary dictionary];
        xar_opt_set(_x, XAR_OPT_COMPRESSION, "bzip2");
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

- (void)setMajorVersion:(uint16_t)majorVersion minorVersion:(uint16_t)minorVersion beforeTreeHash:(NSString *)beforeTreeHash afterTreeHash:(NSString *)afterTreeHash
{
    xar_subdoc_t attributes = xar_subdoc_new(self.x, BINARY_DELTA_ATTRIBUTES_KEY);
    
    xar_subdoc_prop_set(attributes, MAJOR_DIFF_VERSION_KEY, [[NSString stringWithFormat:@"%u", majorVersion] UTF8String]);
    xar_subdoc_prop_set(attributes, MINOR_DIFF_VERSION_KEY, [[NSString stringWithFormat:@"%u", minorVersion] UTF8String]);
    
    xar_subdoc_prop_set(attributes, BEFORE_TREE_SHA1_KEY, [beforeTreeHash UTF8String]);
    xar_subdoc_prop_set(attributes, AFTER_TREE_SHA1_KEY, [afterTreeHash UTF8String]);
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

- (void)addRelativeFilePath:(NSString *)relativeFilePath realFilePath:(nullable NSString *)filePath attributes:(SPUDeltaFileAttributes)attributes permissions:(nullable NSNumber *)permissions
{
    xar_file_t newFile = _xarAddFile(self.fileTable, self.x, relativeFilePath, filePath);
    assert(newFile != NULL);
    
    if ((attributes & SPUDeltaFileAttributesDelete) != 0) {
        xar_prop_set(newFile, DELETE_KEY, "true");
    }
    
    if ((attributes & SPUDeltaFileAttributesExtract) != 0) {
        xar_prop_set(newFile, EXTRACT_KEY, "true");
    }
    
    if ((attributes & SPUDeltaFileAttributesBinaryDiff) != 0) {
        xar_prop_set(newFile, BINARY_DELTA_KEY, "true");
    }
    
    if ((attributes & SPUDeltaFileAttributesModifyPermissions) != 0) {
        assert(permissions != nil);
        if (permissions != nil) {
            xar_prop_set(newFile, MODIFY_PERMISSIONS_KEY, [NSString stringWithFormat:@"%u", permissions.unsignedShortValue].UTF8String);
        }
    }
}

@end
