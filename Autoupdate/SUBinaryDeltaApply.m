//
//  SUBinaryDeltaApply.m
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-01.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#import "SUBinaryDeltaApply.h"
#import "SUBinaryDeltaCommon.h"
#import "SPUDeltaArchiveProtocol.h"
#import "SPUDeltaArchive.h"
#import <CommonCrypto/CommonDigest.h>
#import <Foundation/Foundation.h>
#include "bspatch.h"
#include <stdio.h>
#include <stdlib.h>


#include "AppKitPrevention.h"

static BOOL applyBinaryDeltaToFile(NSString *patchFile, NSString *sourceFilePath, NSString *destinationFilePath)
{
    const char *argv[] = {"/usr/bin/bspatch", [sourceFilePath fileSystemRepresentation], [destinationFilePath fileSystemRepresentation], [patchFile fileSystemRepresentation]};
    BOOL success = (bspatch(4, argv) == 0);
    unlink([patchFile fileSystemRepresentation]);
    return success;
}

BOOL applyBinaryDelta(NSString *source, NSString *destination, NSString *patchFile, BOOL verbose, void (^progressCallback)(double progress), NSError *__autoreleasing *error)
{
    SPUDeltaArchiveHeader *header = nil;
    id<SPUDeltaArchiveProtocol> archive = SPUDeltaArchiveReadPatchAndHeader(patchFile, &header);
    if (archive.error != nil) {
        if (error != NULL) {
            *error = archive.error;
        }
        return NO;
    }

    progressCallback(0/6.0);

    SUBinaryDeltaMajorVersion majorDiffVersion = header.majorVersion;
    uint16_t minorDiffVersion = header.minorVersion;

    unsigned char *expectedBeforeHash = header.beforeTreeHash;
    unsigned char *expectedAfterHash = header.afterTreeHash;
    
    if (majorDiffVersion < SUBinaryDeltaMajorVersionFirst) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to identify diff-version %u in delta.  Giving up.", majorDiffVersion] }];
        }
        return NO;
    }
    
    if (majorDiffVersion < SUBinaryDeltaMajorVersionFirstSupported) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Applying version %u patches is no longer supported.", majorDiffVersion] }];
        }
        return NO;
    }

    if (majorDiffVersion > SUBinaryDeltaMajorVersionLatest) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"A later version is needed to apply this patch (on major version %u, but patch requests version %u).", SUBinaryDeltaMajorVersionLatest, majorDiffVersion] }];
        }
        return NO;
    }
    
    // Reject patches that did not generate valid hierarchical xar container paths
    // These will not succeed to patch using recent versions of BinaryDelta
    if ([[archive class] maySupportSafeExtraction] && majorDiffVersion == SUBinaryDeltaMajorVersion2 && minorDiffVersion < 3) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadCorruptFileError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"This patch version (%u.%u) is too old and potentially unsafe to apply. Please re-generate the patch using the latest version of BinaryDelta or generate_appcast. New version %u.%u patches will still be compatible with older versions of Sparkle.", majorDiffVersion, minorDiffVersion, majorDiffVersion, latestMinorVersionForMajorVersion(majorDiffVersion)] }];
        }
        
        return NO;
    }

    if (expectedBeforeHash == nil || expectedAfterHash == nil) {
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
    
    unsigned char beforeHash[CC_SHA1_DIGEST_LENGTH] = {0};
    if (!getRawHashOfTreeWithVersion(beforeHash, source, majorDiffVersion)) {
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to calculate hash of tree %@", source] }];
        }
        return NO;
    }

    if (memcmp(beforeHash, expectedBeforeHash, CC_SHA1_DIGEST_LENGTH) != 0) {
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Source doesn't have expected hash (%@ != %@).  Giving up.", displayHashFromRawHash(expectedBeforeHash), displayHashFromRawHash(beforeHash)] }];
        }
        return NO;
    }

    if (verbose) {
        fprintf(stderr, "\nCopying files...");
    }

    progressCallback(2/6.0);

    if (!removeTree(destination)) {
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
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to copy %@ to %@", source, destination] }];
        }
        return NO;
    }

    progressCallback(4/6.0);

    if (verbose) {
        fprintf(stderr, "\nPatching...");
    }
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    
    // Ensure error is cleared out in advance
    if (error != NULL) {
        *error = nil;
    }
    
    [archive enumerateItems:^(SPUDeltaArchiveItem *item, BOOL *stop) {
        NSString *relativePath = item.relativeFilePath;
        
        if ([relativePath.pathComponents containsObject:@".."]) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Relative path '%@' contains '..' path component", relativePath] }];
            }
            *stop = YES;
            return;
        }
        
        NSString *sourceFilePath = [source stringByAppendingPathComponent:relativePath];
        NSString *destinationFilePath = [destination stringByAppendingPathComponent:relativePath];
        {
            NSString *destinationParentDirectory = destinationFilePath.stringByDeletingLastPathComponent;
            NSDictionary<NSFileAttributeKey, id> *destinationParentDirectoryAttributes = [fileManager attributesOfItemAtPath:destinationParentDirectory error:NULL];
            
            // It is OK for the directory parent to not exist if it has already been removed
            if (destinationParentDirectoryAttributes != nil) {
                // But if it does exist, make sure the entry in the parent directory we're looking at is good
                // If it's inside a symlink, this is not good in any circumstance
                NSString *fileType = destinationParentDirectoryAttributes[NSFileType];
                if ([fileType isEqualToString:NSFileTypeSymbolicLink]) {
                    if (error != NULL) {
                        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to create patch because '%@' cannot be a symbolic link.", destinationParentDirectory] }];
                    }
                    *stop = YES;
                    return;
                }
            }
        }

        // Don't use -[NSFileManager fileExistsAtPath:] because it will follow symbolic links
        BOOL fileExisted = verbose && [fileManager attributesOfItemAtPath:destinationFilePath error:nil];
        BOOL removedFile = NO;
        
        // Files that have no property set that we check for will get ignored
        // This is important because they aren't part of the delta, just part of the directory structure
        SPUDeltaItemCommands commands = item.commands;
        if ((commands & SPUDeltaItemCommandDelete) != 0) {
            if (!removeTree(destinationFilePath)) {
                if (verbose) {
                    fprintf(stderr, "\n");
                }
                if (error != NULL) {
                    *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"delete: failed to remove %@", destination] }];
                }
                *stop = YES;
                return;
            }

            removedFile = YES;
        }

        if ((commands & SPUDeltaItemCommandClone) != 0) {
            NSString *clonedRelativePath = item.clonedRelativePath;
            if ([clonedRelativePath.pathComponents containsObject:@".."]) {
                if (error != NULL) {
                    *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Relative path for clone '%@' contains '..' path component", clonedRelativePath] }];
                }
                *stop = YES;
                return;
            }
            
            NSString *clonedOriginalPath = [source stringByAppendingPathComponent:clonedRelativePath];
            
            NSError *copyError = nil;
            if (![fileManager copyItemAtPath:clonedOriginalPath toPath:destinationFilePath error:&copyError]) {
                if (verbose) {
                    fprintf(stderr, "\n");
                }
                if (error != NULL) {
                    *error = copyError;
                }
                
                *stop = YES;
                return;
            }
            
            if (verbose) {
                fprintf(stderr, "\n✂️   %s %s -> %s", VERBOSE_CLONED, [clonedRelativePath fileSystemRepresentation], [relativePath fileSystemRepresentation]);
            }
        } else if ((commands & SPUDeltaItemCommandBinaryDiff) != 0) {
            NSString *tempDiffFile = temporaryFilename(@"apply-binary-delta");
            item.physicalFilePath = tempDiffFile;
            
            if (![archive extractItem:item]) {
                if (verbose) {
                    fprintf(stderr, "\n");
                }
                if (error != NULL) {
                    *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to extract diffed file to %@", tempDiffFile], NSUnderlyingErrorKey: (NSError * _Nonnull)archive.error }];
                }
                
                *stop = YES;
                return;
            }
            
            if (!applyBinaryDeltaToFile(tempDiffFile, sourceFilePath, destinationFilePath)) {
                if (verbose) {
                    fprintf(stderr, "\n");
                }
                if (error != NULL) {
                    *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to patch %@ to destination %@", sourceFilePath, destinationFilePath] }];
                }
                *stop = YES;
                return;
            }

            if (verbose) {
                fprintf(stderr, "\n🔨  %s %s", VERBOSE_PATCHED, [relativePath fileSystemRepresentation]);
            }
        } else if ((commands & SPUDeltaItemCommandExtract) != 0) { // extract and permission modifications don't coexist
            item.physicalFilePath = destinationFilePath;
            if (![archive extractItem:item]) {
                if (verbose) {
                    fprintf(stderr, "\n");
                }
                if (error != NULL) {
                    *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to extract file to %@", destinationFilePath], NSUnderlyingErrorKey: (NSError * _Nonnull)archive.error }];
                }
                *stop = YES;
                return;
            }

            if (verbose) {
                if (fileExisted) {
                    fprintf(stderr, "\n✏️  %s %s", VERBOSE_UPDATED, [relativePath fileSystemRepresentation]);
                } else {
                    fprintf(stderr, "\n✅  %s %s", VERBOSE_ADDED, [relativePath fileSystemRepresentation]);
                }
            }
        } else if (verbose && removedFile) {
            fprintf(stderr, "\n❌  %s %s", VERBOSE_DELETED, [relativePath fileSystemRepresentation]);
        }

        if ((commands & SPUDeltaItemCommandModifyPermissions) != 0) {
            mode_t mode = (mode_t)item.permissions;
            if (!modifyPermissions(destinationFilePath, mode)) {
                if (verbose) {
                    fprintf(stderr, "\n");
                }
                if (error != NULL) {
                    *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteNoPermissionError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to modify permissions (%u) on file %@", mode, destinationFilePath] }];
                }
                *stop = YES;
                return;
            }

            if (verbose) {
                fprintf(stderr, "\n👮  %s %s (0%o)", VERBOSE_MODIFIED, [relativePath fileSystemRepresentation], mode);
            }
        }
    }];
    
    [archive close];
    
    // Set error from enumerating items if we have encountered an error and haven't set it yet
    NSError *archiveError = archive.error;
    if (archiveError != nil) {
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL && *error == nil) {
            *error = archiveError;
        }
        return NO;
    }

    progressCallback(5/6.0);

    if (verbose) {
        fprintf(stderr, "\nVerifying destination...");
    }
    
    unsigned char afterHash[CC_SHA1_DIGEST_LENGTH] = {0};
    if (!getRawHashOfTreeWithVersion(afterHash, destination, majorDiffVersion)) {
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to calculate hash of tree %@", destination] }];
        }
        return NO;
    }

    if (memcmp(afterHash, expectedAfterHash, CC_SHA1_DIGEST_LENGTH) != 0) {
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Destination doesn't have expected hash (%@ != %@).  Giving up.", displayHashFromRawHash(expectedAfterHash), displayHashFromRawHash(afterHash)] }];
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
