//
//  SUBinaryDeltaTool.m
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-01.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#include "SUBinaryDeltaApply.h"
#include "SUBinaryDeltaCreate.h"
#include <Foundation/Foundation.h>

static void printUsage(void)
{
    fprintf(stderr, "Usage: BinaryDelta [create | apply] before-tree after-tree patch-file\n");
}

int main(int __unused argc, char __unused *argv[])
{
    @autoreleasepool {
        NSArray *args = [[NSProcessInfo processInfo] arguments];
        if (args.count != 5) {
            printUsage();
            return 1;
        }

        NSString *command = args[1];
        NSString *oldPath = args[2];
        NSString *newPath = args[3];
        NSString *patchFile = args[4];

        BOOL isDirectory;
        if (![[NSFileManager defaultManager] fileExistsAtPath:oldPath isDirectory:&isDirectory] || !isDirectory) {
            fprintf(stderr, "Usage: before-tree must be a directory\n");
            return 1;
        }

        int result;
        if ([command isEqualToString:@"apply"]) {
            result = applyBinaryDelta(oldPath, newPath, patchFile);
        } else if ([command isEqualToString:@"create"]) {
            if (![[NSFileManager defaultManager] fileExistsAtPath:newPath isDirectory:&isDirectory] || !isDirectory) {
                result = 1;
                fprintf(stderr, "Usage: after-tree must be a directory\n");
            } else {
                result = createBinaryDelta(oldPath, newPath, patchFile);
            }
        } else {
            result = 1;
            printUsage();
        }

        return result;
    }
}
