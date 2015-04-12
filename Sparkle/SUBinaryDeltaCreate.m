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
#import <CommonCrypto/CommonDigest.h>
#include <fcntl.h>
#include <fts.h>
#include <libgen.h>
#include <stdio.h>
#include <sys/mman.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <unistd.h>
#include <xar/xar.h>

extern int bsdiff(int argc, const char **argv);

@interface CreateBinaryDeltaOperation : NSOperation
@property (copy) NSString *relativePath;
@property (strong) NSString *resultPath;
@property (strong) NSString *_fromPath;
@property (strong) NSString *_toPath;
- (id)initWithRelativePath:(NSString *)relativePath oldTree:(NSString *)oldTree newTree:(NSString *)newTree;
@end

@implementation CreateBinaryDeltaOperation
@synthesize relativePath = _relativePath;
@synthesize resultPath = _resultPath;
@synthesize _fromPath = _fromPath;
@synthesize _toPath = _toPath;

- (id)initWithRelativePath:(NSString *)relativePath oldTree:(NSString *)oldTree newTree:(NSString *)newTree
{
    if ((self = [super init])) {
        self.relativePath = relativePath;
        self._fromPath = [oldTree stringByAppendingPathComponent:relativePath];
        self._toPath = [newTree stringByAppendingPathComponent:relativePath];
    }
    return self;
}

- (void)main
{
    NSString *temporaryFile = temporaryFilename(@"BinaryDelta");
    const char *argv[] = {"/usr/bin/bsdiff", [self._fromPath fileSystemRepresentation], [self._toPath fileSystemRepresentation], [temporaryFile fileSystemRepresentation]};
    int result = bsdiff(4, argv);
    if (!result)
        self.resultPath = temporaryFile;
}

@end

#define INFO_HASH_KEY @"hash"
#define INFO_TYPE_KEY @"type"
#define INFO_EXECUTABLE_PERMISSIONS_KEY @"executable_permissions"
#define INFO_SIZE_KEY @"size"

static NSDictionary *infoForFile(FTSENT *ent)
{
    NSData *hash = hashOfFileContents(ent);
    if (!hash) {
        return nil;
    }
    
    off_t size = (ent->fts_info != FTS_D) ? ent->fts_statp->st_size : 0;
    
    assert(ent->fts_statp != NULL);
    
    mode_t mode = ent->fts_statp->st_mode;
    mode_t executablePermissions = mode & EXECUTABLE_PERMISSIONS;
    
    return @{INFO_HASH_KEY: hash, INFO_TYPE_KEY: @(ent->fts_info), INFO_EXECUTABLE_PERMISSIONS_KEY : @(executablePermissions), INFO_SIZE_KEY: @(size)};
}

static NSString *absolutePath(NSString *path)
{
    NSURL *url = [[NSURL alloc] initFileURLWithPath:path];
    return  [[url absoluteURL] path];
}

static NSString *temporaryPatchFile(NSString *patchFile)
{
    NSString *path = absolutePath(patchFile);
    NSString *directory = [path stringByDeletingLastPathComponent];
    NSString *file = [path lastPathComponent];
    return [NSString stringWithFormat:@"%@/.%@.tmp", directory, file];
}

#define MIN_FILE_SIZE_FOR_CREATING_DELTA 4096

static BOOL shouldSkipDeltaCompression(NSDictionary* originalInfo, NSDictionary *newInfo)
{
    unsigned long long fileSize = [newInfo[INFO_SIZE_KEY] unsignedLongLongValue];
    if (fileSize < MIN_FILE_SIZE_FOR_CREATING_DELTA) {
        return YES;
    }

    if (!originalInfo) {
        return YES;
    }

    if ([originalInfo[INFO_TYPE_KEY] unsignedShortValue] != [newInfo[INFO_TYPE_KEY] unsignedShortValue]) {
        return YES;
    }
    
    if ([originalInfo[INFO_EXECUTABLE_PERMISSIONS_KEY] unsignedShortValue] != [newInfo[INFO_EXECUTABLE_PERMISSIONS_KEY] unsignedShortValue]) {
        return YES;
    }

    return NO;
}

static BOOL shouldDeleteThenExtract(NSDictionary* originalInfo, NSDictionary *newInfo)
{
    if (!originalInfo) {
        return NO;
    }

    if ([originalInfo[INFO_TYPE_KEY] unsignedShortValue] != [newInfo[INFO_TYPE_KEY] unsignedShortValue]) {
        return YES;
    }
    
    if ([originalInfo[INFO_EXECUTABLE_PERMISSIONS_KEY] unsignedShortValue] != [newInfo[INFO_EXECUTABLE_PERMISSIONS_KEY] unsignedShortValue]) {
        return YES;
    }

    return NO;
}

int createBinaryDelta(NSString *source, NSString *destination, NSString *patchFile)
{
    NSMutableDictionary *originalTreeState = [NSMutableDictionary dictionary];

    const char *sourcePaths[] = {[source fileSystemRepresentation], 0};
    FTS *fts = fts_open((char* const*)sourcePaths, FTS_PHYSICAL | FTS_NOCHDIR, compareFiles);
    if (!fts) {
        perror("fts_open");
        return 1;
    }

    fprintf(stdout, "Processing %s...", [source fileSystemRepresentation]);
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
            fprintf(stderr, "Failed to retrieve info for file %s", ent->fts_path);
            return 1;
        }
        originalTreeState[key] = info;
    }
    fts_close(fts);

    NSString *beforeHashv1_0 = hashOfTreeWithVersion(source, 1, 0);
    if (!beforeHashv1_0) {
        fprintf(stderr, "Failed to generate version 1.0 hash for tree %s ; this patch won't be apply-able from older versions", [source fileSystemRepresentation]);
    }
    
    NSString *beforeHashv1_1 = hashOfTree(source);
    if (!beforeHashv1_1) {
        fprintf(stderr, "Failed to generate latest hash for tree %s", [source fileSystemRepresentation]);
        return 1;
    }

    NSMutableDictionary *newTreeState = [NSMutableDictionary dictionary];
    for (NSString *key in originalTreeState)
    {
        newTreeState[key] = [NSNull null];
    }

    fprintf(stdout, "\nProcessing %s...  ", [destination fileSystemRepresentation]);
    sourcePaths[0] = [destination fileSystemRepresentation];
    fts = fts_open((char* const*)sourcePaths, FTS_PHYSICAL | FTS_NOCHDIR, compareFiles);
    if (!fts) {
        perror("fts_open");
        return 1;
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
            fprintf(stderr, "Failed to retrieve info from file %s", ent->fts_path);
            return 1;
        }
        NSDictionary *oldInfo = originalTreeState[key];

        if ([info isEqual:oldInfo]) {
            [newTreeState removeObjectForKey:key];
        } else {
            newTreeState[key] = info;
            
            if (oldInfo && [oldInfo[INFO_TYPE_KEY] unsignedShortValue] == FTS_D && [info[INFO_TYPE_KEY] unsignedShortValue] != FTS_D) {
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

    NSString *afterHashv1_0 = hashOfTreeWithVersion(destination, 1, 0);
    if (!afterHashv1_0) {
        fprintf(stderr, "Failed to generate version 1.0 hash for tree %s ; this patch won't be apply-able from older versions", [destination fileSystemRepresentation]);
    }
    
    NSString *afterHashv1_1 = hashOfTree(destination);
    if (!afterHashv1_1) {
        fprintf(stderr, "Failed to generate latest hash for tree %s", [destination fileSystemRepresentation]);
        return 1;
    }

    fprintf(stdout, "\nGenerating delta...  ");

    NSString *temporaryFile = temporaryPatchFile(patchFile);
    xar_t x = xar_open([temporaryFile fileSystemRepresentation], WRITE);
    xar_opt_set(x, XAR_OPT_COMPRESSION, "bzip2");
    
    xar_subdoc_t attributes = xar_subdoc_new(x, "binary-delta-attributes");
    
    xar_subdoc_prop_set(attributes, "major-version", LATEST_DELTA_DIFF_MAJOR_VERSION_STR);
    xar_subdoc_prop_set(attributes, "minor-version", LATEST_DELTA_DIFF_MINOR_VERSION_STR);
    
    if (beforeHashv1_0) {
        xar_subdoc_prop_set(attributes, "before-sha1", [beforeHashv1_0 UTF8String]);
    }
    if (afterHashv1_0) {
        xar_subdoc_prop_set(attributes, "after-sha1", [afterHashv1_0 UTF8String]);
    }
    
    xar_subdoc_prop_set(attributes, "before-sha1-v1.1", [beforeHashv1_1 UTF8String]);
    xar_subdoc_prop_set(attributes, "after-sha1-v1.1", [afterHashv1_1 UTF8String]);

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
    for (NSString* key in keys) {
        id value = [newTreeState valueForKey:key];

        if ([value isEqual:[NSNull null]]) {
            xar_file_t newFile = xar_add_frombuffer(x, 0, [key fileSystemRepresentation], (char *)"", 1);
            assert(newFile);
            xar_prop_set(newFile, "delete", "true");
            continue;
        }

        NSDictionary *originalInfo = originalTreeState[key];
        NSDictionary *newInfo = newTreeState[key];
        if (shouldSkipDeltaCompression(originalInfo, newInfo)) {
            NSString *path = [destination stringByAppendingPathComponent:key];
            xar_file_t newFile = xar_add_frompath(x, 0, [key fileSystemRepresentation], [path fileSystemRepresentation]);
            assert(newFile);
            if (shouldDeleteThenExtract(originalInfo, newInfo)) {
                xar_prop_set(newFile, "delete-then-extract", "true");
            }
        } else {
            CreateBinaryDeltaOperation *operation = [[CreateBinaryDeltaOperation alloc] initWithRelativePath:key oldTree:source newTree:destination];
            [deltaQueue addOperation:operation];
            [deltaOperations addObject:operation];
        }
    }

    [deltaQueue waitUntilAllOperationsAreFinished];

    for (CreateBinaryDeltaOperation *operation in deltaOperations) {
        NSString *resultPath = [operation resultPath];
        if (!resultPath) {
            fprintf(stderr, "Failed to create patch from source %s and destination %s\n", [[operation relativePath] fileSystemRepresentation], [resultPath fileSystemRepresentation]);
            return 1;
        }
        xar_file_t newFile = xar_add_frompath(x, 0, [[operation relativePath] fileSystemRepresentation], [resultPath fileSystemRepresentation]);
        assert(newFile);
        xar_prop_set(newFile, "binary-delta", "true");
        unlink([resultPath fileSystemRepresentation]);
    }

    xar_close(x);

    unlink([patchFile fileSystemRepresentation]);
    link([temporaryFile fileSystemRepresentation], [patchFile fileSystemRepresentation]);
    unlink([temporaryFile fileSystemRepresentation]);
    fprintf(stdout, "Done!\n");

    return 0;
}
