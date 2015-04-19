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

#define VERBOSE_FLAG @"--verbose"
#define VERSION_FLAG @"--version"

static void printUsage(void)
{
    fprintf(stderr, "Usage:\n");
    fprintf(stderr, "BinaryDelta create [--verbose --version=<version>] <before-tree> <after-tree> <patch-file>\n");
    fprintf(stderr, "BinaryDelta apply [--verbose] <before-tree> <after-tree> <patch-file>\n");
}

static int runCreateCommand(NSArray *args)
{
    if (args.count < 3 || args.count > 5) {
        printUsage();
        return 1;
    }
    
    if (args.count == 4 && ![args[0] isEqualToString:VERBOSE_FLAG] && ![args[0] hasPrefix:VERSION_FLAG]) {
        printUsage();
        return 1;
    }
    
    if (args.count == 5 && ![args[1] isEqualToString:VERBOSE_FLAG] && ![args[1] hasPrefix:VERSION_FLAG]) {
        printUsage();
        return 1;
    }
    
    BOOL verbose =
        ((args.count >= 4 && [args[0] isEqualToString:VERBOSE_FLAG]) ||
        (args.count >= 5 && [args[1] isEqualToString:VERBOSE_FLAG]));
    
    NSString *versionField = nil;
    if (args.count >= 4 && [args[0] hasPrefix:VERSION_FLAG]) {
        versionField = args[0];
    } else if (args.count >= 5 && [args[1] hasPrefix:VERSION_FLAG]) {
        versionField = args[1];
    }
    
    NSArray *versionComponents = nil;
    if (versionField) {
        versionComponents = [versionField componentsSeparatedByString:@"="];
        if (versionComponents.count != 2) {
            printUsage();
            return 1;
        }
    }
    
    SUBinaryDeltaMajorVersion patchVersion =
        !versionComponents ?
        LATEST_DELTA_DIFF_MAJOR_VERSION :
        (SUBinaryDeltaMajorVersion)[[versionComponents[1] componentsSeparatedByString:@"."][0] intValue]; // ignore minor version if provided

    NSArray *fileArgs = [args subarrayWithRange:NSMakeRange(args.count - 3, 3)];
    
    BOOL isDirectory;
    if (![[NSFileManager defaultManager] fileExistsAtPath:fileArgs[0] isDirectory:&isDirectory] || !isDirectory) {
        fprintf(stderr, "Usage: before-tree must be a directory\n");
        return 1;
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:fileArgs[1] isDirectory:&isDirectory] || !isDirectory) {
        fprintf(stderr, "Usage: after-tree must be a directory\n");
        return 1;
    }
    
    return createBinaryDelta(fileArgs[0], fileArgs[1], fileArgs[2], patchVersion, verbose);
}

static int runApplyCommand(NSArray *args)
{
    if (args.count < 3 || args.count > 4) {
        printUsage();
        return 1;
    }
    
    if (args.count == 4 && ![args[0] isEqualToString:VERBOSE_FLAG]) {
        printUsage();
        return 1;
    }
    
    BOOL verbose = (args.count == 4 && [args[0] isEqualToString:VERBOSE_FLAG]);
    
    NSArray *fileArgs = [args subarrayWithRange:NSMakeRange(args.count - 3, 3)];
    
    BOOL isDirectory;
    if (![[NSFileManager defaultManager] fileExistsAtPath:fileArgs[0] isDirectory:&isDirectory] || !isDirectory) {
        fprintf(stderr, "Usage: before-tree must be a directory\n");
        return 1;
    }
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:fileArgs[2] isDirectory:&isDirectory] || isDirectory) {
        fprintf(stderr, "Usage: patch-file must be a file %d\n", isDirectory);
        return 1;
    }
    
    return applyBinaryDelta(fileArgs[0], fileArgs[1], fileArgs[2], verbose);
}

int main(int __unused argc, char __unused *argv[])
{
    @autoreleasepool {
        NSArray *args = [[NSProcessInfo processInfo] arguments];
        if (args.count < 3) {
            printUsage();
            return 1;
        }

        NSString *command = args[1];
        NSArray *commandArguments = [args subarrayWithRange:NSMakeRange(2, args.count - 2)];
        
        int result;
        if ([command isEqualToString:@"create"]) {
            result = runCreateCommand(commandArguments);
        } else if ([command isEqualToString:@"apply"]) {
            result = runApplyCommand(commandArguments);
        } else {
            result = 1;
            printUsage();
        }
        
        return result;
    }
}
