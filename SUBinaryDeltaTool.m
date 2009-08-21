//
//  SUBinaryDeltaTool.m
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-01.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#define _DARWIN_NO_64_BIT_INODE 1

#include "SUBinaryDeltaCommon.h"
#include "SUBinaryDeltaApply.h"
#include <CommonCrypto/CommonDigest.h>
#include <Foundation/Foundation.h>
#include <dispatch/dispatch.h>
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

static NSDictionary *infoForFile(FTSENT *ent)
{
    NSData *hash = hashOfFile(ent);
    NSNumber *size = nil;
    if (ent->fts_info != FTS_D)
        size = [NSNumber numberWithUnsignedLongLong:ent->fts_statp->st_size];
    return [NSDictionary dictionaryWithObjectsAndKeys:hash, @"hash", [NSNumber numberWithUnsignedShort:ent->fts_info], @"type", size, @"size", nil];
}

static void addBinaryDelta(dispatch_group_t deltaGroup, dispatch_queue_t xarQueue, xar_t x, NSString *relativePath, NSString *oldBasePath, NSString *newBasePath)
{
    NSString *oldPath = [oldBasePath stringByAppendingPathComponent:relativePath];
    NSString *newPath = [newBasePath stringByAppendingPathComponent:relativePath];
    NSString *temporaryFile = temporaryFilename(@"create-binary-delta");

    dispatch_queue_t bsdiffQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    dispatch_retain(xarQueue);
    dispatch_retain(deltaGroup);

    dispatch_group_async(deltaGroup, bsdiffQueue, ^{
        const char *argv[] = {"/usr/bin/bsdiff", [oldPath fileSystemRepresentation], [newPath fileSystemRepresentation], [temporaryFile fileSystemRepresentation]};
        int result = bsdiff(4, argv);

        if (!result) {
            dispatch_group_async(deltaGroup, xarQueue, ^{
                xar_file_t newFile = xar_add_frompath(x, 0, [relativePath fileSystemRepresentation], [temporaryFile fileSystemRepresentation]);
                assert(newFile);
                xar_prop_set(newFile, "binary-delta", "true");
                unlink([temporaryFile fileSystemRepresentation]);
            });
        }
        dispatch_release(xarQueue);
        dispatch_release(deltaGroup);
    });
}

static NSString *absolutePath(NSString *path)
{
    NSURL *url = [[[NSURL alloc] initFileURLWithPath:path] autorelease];
    return  [[url absoluteURL] path];
}

static NSString *temporaryPatchFile(NSString *patchFile)
{
    NSString *path = absolutePath(patchFile);
    NSString *directory = [path stringByDeletingLastPathComponent];
    NSString *file = [path lastPathComponent];
    return [NSString stringWithFormat:@"%@/.%@.tmp", directory, file];
}

static BOOL shouldSkipDeltaCompression(NSString *key, NSDictionary* originalInfo, NSDictionary *newInfo)
{
    unsigned long long fileSize = [[newInfo objectForKey:@"size"] unsignedLongLongValue];
    if (fileSize < 4096)
        return YES;

    if (!originalInfo)
        return YES;

    if ([[originalInfo objectForKey:@"type"] unsignedShortValue] != [[newInfo objectForKey:@"type"] unsignedShortValue])
        return YES;

    return NO;
}

static BOOL shouldDeleteThenExtract(NSString *key, NSDictionary* originalInfo, NSDictionary *newInfo)
{
    if (!originalInfo)
        return NO;

    if ([[originalInfo objectForKey:@"type"] unsignedShortValue] != [[newInfo objectForKey:@"type"] unsignedShortValue])
        return YES;

    return NO;
}

int main(int argc, char **argv)
{
    if (argc != 5) {
usage:
        fprintf(stderr, "Usage: BinaryDelta [create | apply] before-tree after-tree patch-file\n");
        exit(1);
    }

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSString *command = [NSString stringWithUTF8String:argv[1]];
    NSString *oldPath = [NSString stringWithUTF8String:argv[2]];
    NSString *newPath = [NSString stringWithUTF8String:argv[3]];
    NSString *patchFile = [NSString stringWithUTF8String:argv[4]];

    if ([command isEqualToString:@"apply"])
        return applyBinaryDelta(oldPath, newPath, patchFile);
    if (![command isEqualToString:@"create"])
        goto usage;
    
    NSMutableDictionary *originalTreeState = [NSMutableDictionary new];

    const char *sourcePaths[] = {[oldPath fileSystemRepresentation], 0};
    FTS *fts = fts_open((char* const*)sourcePaths, FTS_PHYSICAL | FTS_NOCHDIR, compareFiles);
    if (!fts) {
        perror("fts_open");
        return 1;
    }

    fprintf(stderr, "Processing %s...", [oldPath UTF8String]);
    FTSENT *ent = 0;
    while ((ent = fts_read(fts))) {
        if (ent->fts_info != FTS_F && ent->fts_info != FTS_SL && ent->fts_info != FTS_D)
            continue;

        NSString *key = pathRelativeToDirectory(oldPath, [NSString stringWithUTF8String:ent->fts_path]);
        if (![key length])
            continue;

        NSDictionary *info = infoForFile(ent);
        [originalTreeState setObject:info forKey:key];
    }
    fts_close(fts);

    NSString *beforeHash = hashOfTree(oldPath);

    NSMutableDictionary *newTreeState = [NSMutableDictionary new];
    for (NSString *key in originalTreeState)
    {
        [newTreeState setObject:[NSNull null] forKey:key];
    }

    fprintf(stderr, "\nProcessing %s...  ", [newPath UTF8String]);
    sourcePaths[0] = [newPath fileSystemRepresentation];
    fts = fts_open((char* const*)sourcePaths, FTS_PHYSICAL | FTS_NOCHDIR, compareFiles);
    if (!fts) {
        perror("fts_open");
        return 1;
    }


    while ((ent = fts_read(fts))) {
        if (ent->fts_info != FTS_F && ent->fts_info != FTS_SL && ent->fts_info != FTS_D)
            continue;

        NSString *key = pathRelativeToDirectory(newPath, [NSString stringWithUTF8String:ent->fts_path]);
        if (![key length])
            continue;

        NSDictionary *info = infoForFile(ent);
        NSDictionary *oldInfo = [originalTreeState objectForKey:key];

        if ([info isEqual:oldInfo])
            [newTreeState removeObjectForKey:key];
        else
            [newTreeState setObject:info forKey:key];
    }
    fts_close(fts);

    NSString *afterHash = hashOfTree(newPath);

    fprintf(stderr, "\nGenerating delta...  ");

    dispatch_group_t deltaGroup = dispatch_group_create();
    dispatch_queue_t xarQueue = dispatch_queue_create("xar", 0);

    NSString *temporaryFile = temporaryPatchFile(patchFile);
    __block xar_t x;
    dispatch_sync(xarQueue, ^{
        x = xar_open([temporaryFile fileSystemRepresentation], WRITE);
        xar_opt_set(x, XAR_OPT_COMPRESSION, "bzip2");
        xar_subdoc_t attributes = xar_subdoc_new(x, "binary-delta-attributes");
        xar_subdoc_prop_set(attributes, "before-sha1", [beforeHash UTF8String]);
        xar_subdoc_prop_set(attributes, "after-sha1", [afterHash UTF8String]);
    });

    NSArray *keys = [[newTreeState allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString* key in keys) {
        id value = [newTreeState valueForKey:key];

        if ([value isEqual:[NSNull null]]) {
            dispatch_group_async(deltaGroup, xarQueue, ^{
                xar_file_t newFile = xar_add_frombuffer(x, 0, [key fileSystemRepresentation], "", 1);
                assert(newFile);
                xar_prop_set(newFile, "delete", "true");
            });
            continue;
        }

        NSDictionary *originalInfo = [originalTreeState objectForKey:key];
        NSDictionary *newInfo = [newTreeState objectForKey:key];
        if (shouldSkipDeltaCompression(key, originalInfo, newInfo)) {
            NSString *path = [newPath stringByAppendingPathComponent:key];
            __block BOOL deleteFirst = shouldDeleteThenExtract(key, originalInfo, newInfo);
            dispatch_group_async(deltaGroup, xarQueue, ^{
                xar_file_t newFile = xar_add_frompath(x, 0, [key fileSystemRepresentation], [path fileSystemRepresentation]);
                assert(newFile);
                if (deleteFirst)
                    xar_prop_set(newFile, "delete-then-extract", "true");
            });
        } else
            addBinaryDelta(deltaGroup, xarQueue, x, key, oldPath, newPath);
    }

    dispatch_group_wait(deltaGroup, UINT64_MAX);
    dispatch_sync(xarQueue, ^{ xar_close(x); });

    unlink([patchFile fileSystemRepresentation]);
    link([temporaryFile fileSystemRepresentation], [patchFile fileSystemRepresentation]);
    unlink([temporaryFile fileSystemRepresentation]);
    fprintf(stderr, "Done!\n");

    [pool drain];
    return 0;
}
