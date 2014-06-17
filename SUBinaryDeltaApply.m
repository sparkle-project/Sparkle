//
//  SUBinaryDeltaApply.m
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-01.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#import "SUBinaryDeltaApply.h"
#import "SUBinaryDeltaCommon.h"
#include <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#include <bspatch.h>
#include <stdio.h>
#include <stdlib.h>
#include <xar/xar.h>

static void applyBinaryDeltaToFile(xar_t x, xar_file_t file, NSString *sourceFilePath, NSString *destinationFilePath)
{
    NSString *patchFile = temporaryFilename(@"apply-binary-delta");
    xar_extract_tofile(x, file, [patchFile fileSystemRepresentation]);
    const char *argv[] = {"/usr/bin/bspatch", [sourceFilePath fileSystemRepresentation], [destinationFilePath fileSystemRepresentation], [patchFile fileSystemRepresentation]};
    bspatch(4, (char **)argv);
    unlink([patchFile fileSystemRepresentation]);
}

int applyBinaryDelta(NSString *source, NSString *destination, NSString *patchFile)
{
    xar_t x = xar_open([patchFile UTF8String], READ);
    if (!x) {
        fprintf(stderr, "Unable to open %s. Giving up.\n", [patchFile UTF8String]);
        return 1;
    }

    NSString *expectedBeforeHash = nil;
    NSString *expectedAfterHash = nil;
    xar_subdoc_t subdoc;
    for (subdoc = xar_subdoc_first(x); subdoc; subdoc = xar_subdoc_next(subdoc)) {
        if (!strcmp(xar_subdoc_name(subdoc), "binary-delta-attributes")) {
            const char *value = 0;
            xar_subdoc_prop_get(subdoc, "before-sha1", &value);
            if (value)
                expectedBeforeHash = @(value);

            xar_subdoc_prop_get(subdoc, "after-sha1", &value);
            if (value)
                expectedAfterHash = @(value);
        }
    }

    if (!expectedBeforeHash || !expectedAfterHash) {
        fprintf(stderr, "Unable to find before-sha1 or after-sha1 metadata in delta.  Giving up.\n");
        return 1;
    }

    fprintf(stderr, "Verifying source...  ");
    NSString *beforeHash = hashOfTree(source);

    if (![beforeHash isEqualToString:expectedBeforeHash]) {
        fprintf(stderr, "Source doesn't have expected hash (%s != %s).  Giving up.\n", [expectedBeforeHash UTF8String], [beforeHash UTF8String]);
        return 1;
    }

    fprintf(stderr, "\nCopying files...  ");
    removeTree(destination);
    copyTree(source, destination);

    fprintf(stderr, "\nPatching... ");
    xar_file_t file;
    xar_iter_t iter = xar_iter_new();
    for (file = xar_file_first(x, iter); file; file = xar_file_next(iter)) {
        NSString *path = @(xar_get_path(file));
        NSString *sourceFilePath = [source stringByAppendingPathComponent:path];
        NSString *destinationFilePath = [destination stringByAppendingPathComponent:path];

        const char *value;
        if (!xar_prop_get(file, "delete", &value) || !xar_prop_get(file, "delete-then-extract", &value)) {
            removeTree(destinationFilePath);
            if (!xar_prop_get(file, "delete", &value))
                continue;
        }

        if (!xar_prop_get(file, "binary-delta", &value))
            applyBinaryDeltaToFile(x, file, sourceFilePath, destinationFilePath);
        else
            xar_extract_tofile(x, file, [destinationFilePath fileSystemRepresentation]);
    }
    xar_close(x);

    fprintf(stderr, "\nVerifying destination...  ");
    NSString *afterHash = hashOfTree(destination);

    if (![afterHash isEqualToString:expectedAfterHash]) {
        fprintf(stderr, "Destination doesn't have expected hash (%s != %s).  Giving up.\n", [expectedAfterHash UTF8String], [afterHash UTF8String]);
        removeTree(destination);
        return 1;
    }

    fprintf(stderr, "\nDone!\n");
    return 0;
}
