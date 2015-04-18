//
//  SUBinaryDeltaTool.m
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-01.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#include "SUBinaryDeltaApply.h"
#include "SUBinaryDeltaCreate.h"
#import "SUBinaryDeltaCommon.h"
#include <Foundation/Foundation.h>

static void printUsage(void)
{
    fprintf(stderr, "Usage:\n");
    fprintf(stderr, "BinaryDelta create [--version=<version>] <before-tree> <after-tree> <patch-file>\n");
    fprintf(stderr, "BinaryDelta apply <before-tree> <after-tree> <patch-file>\n");
}

int main(int __unused argc, char __unused *argv[])
{
    @autoreleasepool {
        NSArray *args = [[NSProcessInfo processInfo] arguments];
        if (args.count < 5 || args.count > 6) {
            printUsage();
            return 1;
        }

        NSString *command = args[1];
        
        if (![command isEqualToString:@"create"] && args.count > 5) {
            printUsage();
            return 1;
        }
        
        SUBinaryDeltaMajorVersion patchVersion;
        NSString *versionField = ([command isEqualToString:@"create"] && args.count == 6) ? args[2] : nil;
        if (!versionField) {
            patchVersion = LATEST_DELTA_DIFF_MAJOR_VERSION;
        } else {
            NSArray *versionComponents = [versionField componentsSeparatedByString:@"="];
            if (versionComponents.count != 2 || ![versionComponents[0] isEqualToString:@"--version"]) {
                printUsage();
                return 1;
            }
            // Ignore minor version if it's supplied
            patchVersion = (SUBinaryDeltaMajorVersion)[[versionComponents[1] componentsSeparatedByString:@"."][0] intValue];
        }
        
        NSString *oldPath = args[args.count - 3];
        NSString *newPath = args[args.count - 2];
        NSString *patchFile = args[args.count - 1];

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
                result = createBinaryDelta(oldPath, newPath, patchFile, patchVersion);
            }
        } else {
            result = 1;
            printUsage();
        }

        return result;
    }
}
