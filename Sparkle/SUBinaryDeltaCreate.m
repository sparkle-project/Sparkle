//
//  SUBinaryDeltaCreate.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/9/15.
//  Copyright (c) 2015 Sparkle Project. All rights reserved.
//

#define _DARWIN_NO_64_BIT_INODE 1

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

static NSDictionary *infoForFile(FTSENT *ent)
{
    NSData *hash = hashOfFile(ent);
    NSNumber *size = @0;
    if (ent->fts_info != FTS_D) {
        size = @(ent->fts_statp->st_size);
    }
    return @{@"hash": hash, @"type": @(ent->fts_info), @"size": size};
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

static BOOL shouldSkipDeltaCompression(NSString * __unused key, NSDictionary* originalInfo, NSDictionary *newInfo)
{
    unsigned long long fileSize = [newInfo[@"size"] unsignedLongLongValue];
    if (fileSize < 4096) {
        return YES;
    }

    if (!originalInfo) {
        return YES;
    }

    if ([originalInfo[@"type"] unsignedShortValue] != [newInfo[@"type"] unsignedShortValue]) {
        return YES;
    }

    return NO;
}

static BOOL shouldDeleteThenExtract(NSString * __unused key, NSDictionary* originalInfo, NSDictionary *newInfo)
{
    if (!originalInfo) {
        return NO;
    }

    if ([originalInfo[@"type"] unsignedShortValue] != [newInfo[@"type"] unsignedShortValue]) {
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

    fprintf(stdout, "Processing %s...", [source UTF8String]);
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
        originalTreeState[key] = info;
    }
    fts_close(fts);

    NSString *beforeHash = hashOfTree(source);

    NSMutableDictionary *newTreeState = [NSMutableDictionary dictionary];
    for (NSString *key in originalTreeState)
    {
        newTreeState[key] = [NSNull null];
    }

    fprintf(stdout, "\nProcessing %s...  ", [destination UTF8String]);
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
        NSDictionary *oldInfo = originalTreeState[key];

        if ([info isEqual:oldInfo]) {
            [newTreeState removeObjectForKey:key];
        } else {
            newTreeState[key] = info;
            
            if (oldInfo && [oldInfo[@"type"] unsignedShortValue] == FTS_D && [info[@"type"] unsignedShortValue] != FTS_D) {
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

    NSString *afterHash = hashOfTree(destination);

    fprintf(stdout, "\nGenerating delta...  ");

    NSString *temporaryFile = temporaryPatchFile(patchFile);
    xar_t x = xar_open([temporaryFile fileSystemRepresentation], WRITE);
    xar_opt_set(x, XAR_OPT_COMPRESSION, "bzip2");
    xar_subdoc_t attributes = xar_subdoc_new(x, "binary-delta-attributes");
    xar_subdoc_prop_set(attributes, "before-sha1", [beforeHash UTF8String]);
    xar_subdoc_prop_set(attributes, "after-sha1", [afterHash UTF8String]);

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
        if (shouldSkipDeltaCompression(key, originalInfo, newInfo)) {
            NSString *path = [destination stringByAppendingPathComponent:key];
            xar_file_t newFile = xar_add_frompath(x, 0, [key fileSystemRepresentation], [path fileSystemRepresentation]);
            assert(newFile);
            if (shouldDeleteThenExtract(key, originalInfo, newInfo)) {
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
