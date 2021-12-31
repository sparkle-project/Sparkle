//
//  SUBinaryDeltaTool.m
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-01.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#import "SUBinaryDeltaApply.h"
#import "SUBinaryDeltaCreate.h"
#import "SPUDeltaArchive.h"
#import "SPUDeltaArchiveProtocol.h"
#import <Foundation/Foundation.h>

#define VERBOSE_FLAG @"--verbose"
#define VERSION_FLAG @"--version"

#define CREATE_COMMAND @"create"
#define APPLY_COMMAND @"apply"
#define VERSION_COMMAND @"version"
#define VERSION_ALTERNATE_COMMAND @"--version"

#include "AppKitPrevention.h"

static void printUsage(NSString *programName)
{
    fprintf(stderr, "Usage:\n");
    fprintf(stderr, "%s create [--verbose] [--version=<version>] <before-tree> <after-tree> <patch-file>\n", [programName UTF8String]);
    fprintf(stderr, "%s apply [--verbose] <before-tree> <after-tree> <patch-file>\n", [programName UTF8String]);
    fprintf(stderr, "%s version [<patch-file>]\n", [programName UTF8String]);
}

static BOOL runCreateCommand(NSString *programName, NSArray<NSString *> *args)
{
    if (args.count < 3 || args.count > 5) {
        printUsage(programName);
        return NO;
    }

    NSUInteger numberOflagsFound = 0;
    NSUInteger verboseIndex = [args indexOfObject:VERBOSE_FLAG];
    NSUInteger versionIndex = NSNotFound;
    for (NSUInteger argumentIndex = 0; argumentIndex < args.count; ++argumentIndex) {
        if ([args[argumentIndex] hasPrefix:VERSION_FLAG]) {
            versionIndex = argumentIndex;
            break;
        }
    }

    if (verboseIndex != NSNotFound) {
        ++numberOflagsFound;
    }
    if (versionIndex != NSNotFound) {
        ++numberOflagsFound;
    }

    if (args.count - numberOflagsFound < 3) {
        printUsage(programName);
        return NO;
    }

    BOOL verbose = (verboseIndex != NSNotFound);
    NSString *versionField = (versionIndex != NSNotFound) ? args[versionIndex] : nil;

    NSArray<NSString *> *versionComponents = nil;
    if (versionField) {
        versionComponents = [versionField componentsSeparatedByString:@"="];
        if (versionComponents.count != 2) {
            printUsage(programName);
            return NO;
        }
    }

    SUBinaryDeltaMajorVersion patchVersion =
        !versionComponents ?
        LATEST_DELTA_DIFF_MAJOR_VERSION :
        (SUBinaryDeltaMajorVersion)[[versionComponents[1] componentsSeparatedByString:@"."][0] intValue]; // ignore minor version if provided

    if (patchVersion < FIRST_DELTA_DIFF_MAJOR_VERSION) {
        fprintf(stderr, "Version provided (%u) is not valid\n", patchVersion);
        return NO;
    }
    
    if (patchVersion < FIRST_SUPPORTED_DELTA_MAJOR_VERSION) {
        fprintf(stderr, "Creating version %u patches is no longer supported.\n", patchVersion);
        return NO;
    }

    if (patchVersion > LATEST_DELTA_DIFF_MAJOR_VERSION) {
        fprintf(stderr, "This program is too old to create a version %u patch, or the version number provided is invalid\n", patchVersion);
        return NO;
    }

    NSMutableArray *fileArgs = [NSMutableArray array];
    for (NSString *argument in args) {
        if (![argument hasPrefix:VERSION_FLAG] && ![argument isEqualToString:VERBOSE_FLAG]) {
            [fileArgs addObject:argument];
        }
    }

    if (fileArgs.count != 3) {
        printUsage(programName);
        return NO;
    }

    NSString *sourcePath = fileArgs[0];
    NSString *destPath = fileArgs[1];
    NSString *patchPath = fileArgs[2];

    BOOL isDirectory;
    if (![[NSFileManager defaultManager] fileExistsAtPath:sourcePath isDirectory:&isDirectory] || !isDirectory) {
        printUsage(programName);
        fprintf(stderr, "Error: before-tree must be a directory\n");
        return NO;
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:destPath isDirectory:&isDirectory] || !isDirectory) {
        printUsage(programName);
        fprintf(stderr, "Error: after-tree must be a directory\n");
        return NO;
    }

    NSError *createDiffError = nil;
    if (!createBinaryDelta(sourcePath, destPath, patchPath, patchVersion, verbose, &createDiffError)) {
        fprintf(stderr, "%s\n", [createDiffError.localizedDescription UTF8String]);
        return NO;
    }

    return YES;
}

static BOOL runApplyCommand(NSString *programName, NSArray *args)
{
    if (args.count < 3 || args.count > 4) {
        printUsage(programName);
        return NO;
    }

    BOOL verbose = [args containsObject:VERBOSE_FLAG];

    if (args.count == 4 && !verbose) {
        printUsage(programName);
        return NO;
    }

    NSMutableArray *fileArgs = [NSMutableArray array];
    for (NSString *argument in args) {
        if (![argument isEqualToString:VERBOSE_FLAG]) {
            [fileArgs addObject:argument];
        }
    }

    if (fileArgs.count != 3) {
        printUsage(programName);
        return NO;
    }

    BOOL isDirectory;
    if (![[NSFileManager defaultManager] fileExistsAtPath:fileArgs[0] isDirectory:&isDirectory] || !isDirectory) {
        printUsage(programName);
        fprintf(stderr, "Error: before-tree must be a directory\n");
        return NO;
    }

    if (![[NSFileManager defaultManager] fileExistsAtPath:fileArgs[2] isDirectory:&isDirectory] || isDirectory) {
        printUsage(programName);
        fprintf(stderr, "Error: patch-file must be a file %d\n", isDirectory);
        return NO;
    }

    NSError *applyDiffError = nil;
    if (!applyBinaryDelta(fileArgs[0], fileArgs[1], fileArgs[2], verbose, ^(__unused double x){}, &applyDiffError)) {
        fprintf(stderr, "%s\n", [applyDiffError.localizedDescription UTF8String]);
        return NO;
    }

    return YES;
}

static BOOL runVersionCommand(NSString *programName, NSArray *args)
{
    if (args.count > 1) {
        printUsage(programName);
        return NO;
    }

    if (args.count == 0) {
        fprintf(stdout, "%u.%u\n", LATEST_DELTA_DIFF_MAJOR_VERSION, latestMinorVersionForMajorVersion(LATEST_DELTA_DIFF_MAJOR_VERSION));
    } else {
        NSString *patchFile = args[0];
        
        uint16_t majorDiffVersion = 0;
        uint16_t minorDiffVersion = 0;
        
        id<SPUDeltaArchiveProtocol> archive = SPUDeltaArchiveForReading(patchFile);
        if (archive == nil) {
            fprintf(stderr, "Unable to open patch %s\n", [patchFile fileSystemRepresentation]);
            return NO;
        }
        
        SPUDeltaArchiveHeader *header = [archive readHeader];
        if (header.majorVersion < FIRST_DELTA_DIFF_MAJOR_VERSION) {
            fprintf(stderr, "Unable to retrieve version information from patch %s\n", [patchFile fileSystemRepresentation]);
            return NO;
        }
        
        fprintf(stdout, "%u.%u\n", majorDiffVersion, minorDiffVersion);
    }

    return YES;
}

int main(int __unused argc, char __unused *argv[])
{
    @autoreleasepool {
        NSArray<NSString *> *args = [[NSProcessInfo processInfo] arguments];
        NSString *programName = [args[0] lastPathComponent];

        if (args.count < 2) {
            printUsage(programName);
            return 1;
        }

        NSString *command = args[1];
        NSArray *commandArguments = [args subarrayWithRange:NSMakeRange(2, args.count - 2)];

        BOOL result;
        if ([command isEqualToString:CREATE_COMMAND]) {
            result = runCreateCommand(programName, commandArguments);
        } else if ([command isEqualToString:APPLY_COMMAND]) {
            result = runApplyCommand(programName, commandArguments);
        } else if ([command isEqualToString:VERSION_COMMAND] || [command isEqualToString:VERSION_ALTERNATE_COMMAND]) {
            result = runVersionCommand(programName, commandArguments);
        } else {
            result = NO;
            printUsage(programName);
        }

        return result ? 0 : 1;
    }
}
