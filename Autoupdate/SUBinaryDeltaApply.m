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
#include "bspatch.h"
#include <stdio.h>
#include <stdlib.h>
#include <xar/xar.h>
#include <Availability.h>


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

static BOOL applyBinaryDeltaToFile(xar_t x, xar_file_t file, NSString *sourceFilePath, NSString *destinationFilePath)
{
    NSString *patchFile = temporaryFilename(@"apply-binary-delta");
    xar_extract_tofile(x, file, [patchFile fileSystemRepresentation]);
    const char *argv[] = {"/usr/bin/bspatch", [sourceFilePath fileSystemRepresentation], [destinationFilePath fileSystemRepresentation], [patchFile fileSystemRepresentation]};
    BOOL success = (bspatch(4, argv) == 0);
    unlink([patchFile fileSystemRepresentation]);
    return success;
}

BOOL applyBinaryDelta(NSString *source, NSString *destination, NSString *patchFile, BOOL verbose, void (^progressCallback)(double progress), NSError *__autoreleasing *error)
{
    xar_t x = xar_open([patchFile fileSystemRepresentation], READ);
    if (!x) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to open %@. Giving up.", patchFile] }];
        }
        return NO;
    }

    SUBinaryDeltaMajorVersion majorDiffVersion = FIRST_DELTA_DIFF_MAJOR_VERSION;
    int minorDiffVersion = 0;

    NSString *expectedBeforeHashv1 = nil;
    NSString *expectedAfterHashv1 = nil;

    NSString *expectedNewBeforeHash = nil;
    NSString *expectedNewAfterHash = nil;

    progressCallback(0/6.0);

    xar_subdoc_t subdoc;
    for (subdoc = xar_subdoc_first(x); subdoc; subdoc = xar_subdoc_next(subdoc)) {
        if (!strcmp(xar_subdoc_name(subdoc), BINARY_DELTA_ATTRIBUTES_KEY)) {
            const char *value = 0;

            // available in version 2.0 or later
            xar_subdoc_prop_get(subdoc, MAJOR_DIFF_VERSION_KEY, &value);
            if (value)
                majorDiffVersion = (SUBinaryDeltaMajorVersion)[@(value) intValue];

            // available in version 2.0 or later
            xar_subdoc_prop_get(subdoc, MINOR_DIFF_VERSION_KEY, &value);
            if (value)
                minorDiffVersion = [@(value) intValue];

            // available in version 2.0 or later
            xar_subdoc_prop_get(subdoc, BEFORE_TREE_SHA1_KEY, &value);
            if (value)
                expectedNewBeforeHash = @(value);

            // available in version 2.0 or later
            xar_subdoc_prop_get(subdoc, AFTER_TREE_SHA1_KEY, &value);
            if (value)
                expectedNewAfterHash = @(value);

            // only available in version 1.0
            xar_subdoc_prop_get(subdoc, BEFORE_TREE_SHA1_OLD_KEY, &value);
            if (value)
                expectedBeforeHashv1 = @(value);

            // only available in version 1.0
            xar_subdoc_prop_get(subdoc, AFTER_TREE_SHA1_OLD_KEY, &value);
            if (value)
                expectedAfterHashv1 = @(value);
        }
    }

    if (majorDiffVersion < FIRST_DELTA_DIFF_MAJOR_VERSION) {
        xar_close(x);
        
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to identify diff-version %u in delta.  Giving up.", majorDiffVersion] }];
        }
        return NO;
    }

    if (majorDiffVersion > LATEST_DELTA_DIFF_MAJOR_VERSION) {
        xar_close(x);
        
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"A later version is needed to apply this patch (on major version %u, but patch requests version %u).", LATEST_DELTA_DIFF_MAJOR_VERSION, majorDiffVersion] }];
        }
        return NO;
    }
    
#if HAS_XAR_GET_SAFE_PATH
    // Reject patches that did not generate valid hierarchical xar container paths
    // These will not succeed to patch using recent versions of BinaryDelta
    if ((majorDiffVersion == SUBinaryDeltaMajorVersion2 && minorDiffVersion < 3) || (majorDiffVersion == SUBinaryDeltaMajorVersion1 && minorDiffVersion < 2)) {
        xar_close(x);
        
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"This patch version (%u.%u) is too old and potentially unsafe to apply. Please re-generate the patch using the latest version of BinaryDelta or generate_appcast. New version %u.%u patches will still be compatible with older versions of Sparkle.", majorDiffVersion, minorDiffVersion, majorDiffVersion, latestMinorVersionForMajorVersion(majorDiffVersion)] }];
        }
        
        return NO;
    }
#endif

    BOOL usesNewTreeHash = MAJOR_VERSION_IS_AT_LEAST(majorDiffVersion, SUBinaryDeltaMajorVersion2);

    NSString *expectedBeforeHash = usesNewTreeHash ? expectedNewBeforeHash : expectedBeforeHashv1;
    NSString *expectedAfterHash = usesNewTreeHash ? expectedNewAfterHash : expectedAfterHashv1;

    if (!expectedBeforeHash || !expectedAfterHash) {
        xar_close(x);
        
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{ NSLocalizedDescriptionKey: @"Unable to find before-sha1 or after-sha1 metadata in delta.  Giving up." }];
        }
        return NO;
    }

    if (verbose) {
        fprintf(stderr, "Applying version %u.%u patch...\n", majorDiffVersion, minorDiffVersion);
        fprintf(stderr, "Verifying source...");
    }

    progressCallback(1/6.0);

    NSString *beforeHash = hashOfTreeWithVersion(source, majorDiffVersion);
    if (!beforeHash) {
        xar_close(x);
        
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to calculate hash of tree %@", source] }];
        }
        return NO;
    }

    if (![beforeHash isEqualToString:expectedBeforeHash]) {
        xar_close(x);
        
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Source doesn't have expected hash (%@ != %@).  Giving up.", expectedBeforeHash, beforeHash] }];
        }
        return NO;
    }

    if (verbose) {
        fprintf(stderr, "\nCopying files...");
    }

    progressCallback(2/6.0);

    if (!removeTree(destination)) {
        xar_close(x);
        
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to remove %@", destination] }];
        }
        return NO;
    }

    progressCallback(3/6.0);

    if (!copyTree(source, destination)) {
        xar_close(x);
        
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to copy %@ to %@", source, destination] }];
        }
        return NO;
    }

    progressCallback(4/6.0);

    BOOL hasExtractKeyAvailable = MAJOR_VERSION_IS_AT_LEAST(majorDiffVersion, SUBinaryDeltaMajorVersion2);

    if (verbose) {
        fprintf(stderr, "\nPatching...");
    }
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    xar_file_t file;
    xar_iter_t iter = xar_iter_new();
    for (file = xar_file_first(x, iter); file; file = xar_file_next(iter)) {
        char *pathCString;
#if HAS_XAR_GET_SAFE_PATH
        if (xar_get_safe_path != NULL) {
            pathCString = xar_get_safe_path(file);
        }
        else
#endif
        {
            pathCString = xar_get_path(file);
        }
        
        if (pathCString == NULL) {
            continue;
        }
        
        NSString *path = @(pathCString);
        if ([path.pathComponents containsObject:@".."]) {
            xar_close(x);
            
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Relative path '%@' contains '..' path component", path] }];
            }
            return NO;
        }
        
        NSString *sourceFilePath = [source stringByAppendingPathComponent:path];
        NSString *destinationFilePath = [destination stringByAppendingPathComponent:path];
        {
            NSString *destinationParentDirectory = destinationFilePath.stringByDeletingLastPathComponent;
            NSDictionary<NSFileAttributeKey, id> *destinationParentDirectoryAttributes = [fileManager attributesOfItemAtPath:destinationParentDirectory error:NULL];
            
            // It is OK for the directory parent to not exist if it has already been removed
            if (destinationParentDirectoryAttributes != nil) {
                // But if it does exist, make sure the entry in the parent directory we're looking at is good
                // If it's inside a symlink, this is not good in any circumstance
                NSString *fileType = destinationParentDirectoryAttributes[NSFileType];
                if ([fileType isEqualToString:NSFileTypeSymbolicLink]) {
                    xar_close(x);
                    
                    if (error != NULL) {
                        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to create patch because '%@' cannot be a symbolic link.", destinationParentDirectory] }];
                    }
                    return NO;
                }
            }
        }

        // Don't use -[NSFileManager fileExistsAtPath:] because it will follow symbolic links
        BOOL fileExisted = verbose && [fileManager attributesOfItemAtPath:destinationFilePath error:nil];
        BOOL removedFile = NO;
        
        // Files that have no property set that we check for will get ignored
        // This is important because they aren't part of the delta, just part of the directory structure

        const char *value;
        if (!xar_prop_get(file, DELETE_KEY, &value) || (!hasExtractKeyAvailable && !xar_prop_get(file, DELETE_THEN_EXTRACT_OLD_KEY, &value))) {
            if (!removeTree(destinationFilePath)) {
                xar_close(x);
                
                if (verbose) {
                    fprintf(stderr, "\n");
                }
                if (error != NULL) {
                    *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ or %@: failed to remove %@", @DELETE_KEY, @DELETE_THEN_EXTRACT_OLD_KEY, destination] }];
                }
                return NO;
            }
            if (!hasExtractKeyAvailable && !xar_prop_get(file, DELETE_KEY, &value)) {
                if (verbose) {
                    fprintf(stderr, "\n❌  %s %s", VERBOSE_DELETED, [path fileSystemRepresentation]);
                }
                continue;
            }

            removedFile = YES;
        }

        if (!xar_prop_get(file, BINARY_DELTA_KEY, &value)) {
            if (!applyBinaryDeltaToFile(x, file, sourceFilePath, destinationFilePath)) {
                xar_close(x);
                
                if (verbose) {
                    fprintf(stderr, "\n");
                }
                if (error != NULL) {
                    *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to patch %@ to destination %@", sourceFilePath, destinationFilePath] }];
                }
                return NO;
            }

            if (verbose) {
                fprintf(stderr, "\n🔨  %s %s", VERBOSE_PATCHED, [path fileSystemRepresentation]);
            }
        } else if ((hasExtractKeyAvailable && !xar_prop_get(file, EXTRACT_KEY, &value)) || (!hasExtractKeyAvailable && xar_prop_get(file, MODIFY_PERMISSIONS_KEY, &value))) { // extract and permission modifications don't coexist

            if (xar_extract_tofile(x, file, [destinationFilePath fileSystemRepresentation]) != 0) {
                xar_close(x);
                
                if (verbose) {
                    fprintf(stderr, "\n");
                }
                if (error != NULL) {
                    *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to extract file to %@", destinationFilePath] }];
                }
                return NO;
            }

            if (verbose) {
                if (fileExisted) {
                    fprintf(stderr, "\n✏️  %s %s", VERBOSE_UPDATED, [path fileSystemRepresentation]);
                } else {
                    fprintf(stderr, "\n✅  %s %s", VERBOSE_ADDED, [path fileSystemRepresentation]);
                }
            }
        } else if (verbose && removedFile) {
            fprintf(stderr, "\n❌  %s %s", VERBOSE_DELETED, [path fileSystemRepresentation]);
        }

        if (!xar_prop_get(file, MODIFY_PERMISSIONS_KEY, &value)) {
            mode_t mode = (mode_t)[[NSString stringWithUTF8String:value] intValue];
            if (!modifyPermissions(destinationFilePath, mode)) {
                xar_close(x);
                
                if (verbose) {
                    fprintf(stderr, "\n");
                }
                if (error != NULL) {
                    *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteNoPermissionError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to modify permissions (%@) on file %@", @(value), destinationFilePath] }];
                }
                return NO;
            }

            if (verbose) {
                fprintf(stderr, "\n👮  %s %s (0%o)", VERBOSE_MODIFIED, [path fileSystemRepresentation], mode);
            }
        }
    }
    
    xar_close(x);

    progressCallback(5/6.0);

    if (verbose) {
        fprintf(stderr, "\nVerifying destination...");
    }
    NSString *afterHash = hashOfTreeWithVersion(destination, majorDiffVersion);
    if (!afterHash) {
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to calculate hash of tree %@", destination] }];
        }
        return NO;
    }

    if (![afterHash isEqualToString:expectedAfterHash]) {
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Destination doesn't have expected hash (%@ != %@).  Giving up.", expectedAfterHash, afterHash] }];
        }
        removeTree(destination);
        return NO;
    }

    progressCallback(6/6.0);

    if (verbose) {
        fprintf(stderr, "\nDone!\n");
    }
    return YES;
}
