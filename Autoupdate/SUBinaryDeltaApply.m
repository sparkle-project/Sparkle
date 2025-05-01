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
#import <sys/stat.h>


#include "AppKitPrevention.h"

static BOOL applyBinaryDeltaToFile(NSString *patchFile, NSString *sourceFilePath, NSString *destinationFilePath)
{
    const char *argv[] = {"/usr/bin/bspatch", [sourceFilePath fileSystemRepresentation], [destinationFilePath fileSystemRepresentation], [patchFile fileSystemRepresentation]};
    BOOL success = (bspatch(4, argv) == 0);
    unlink([patchFile fileSystemRepresentation]);
    return success;
}

BOOL applyBinaryDelta(NSString *source, NSString *finalDestination, NSString *patchFile, BOOL verbose, void (^progressCallback)(double progress), NSError *__autoreleasing *error)
{
    SPUDeltaArchiveHeader *header = nil;
    id<SPUDeltaArchiveProtocol> archive = SPUDeltaArchiveReadPatchAndHeader(patchFile, &header);
    if (archive.error != nil) {
        if (error != NULL) {
            *error = archive.error;
        }
        return NO;
    }

    progressCallback(0/7.0);

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

    progressCallback(1/7.0);
    
    unsigned char beforeHash[BINARY_DELTA_HASH_LENGTH] = {0};
    if (!getRawHashOfTreeWithVersion(beforeHash, source, majorDiffVersion)) {
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to calculate hash of tree %@", source] }];
        }
        return NO;
    }
    
    if (memcmp(beforeHash, expectedBeforeHash, BINARY_DELTA_HASH_LENGTH) != 0) {
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

    progressCallback(2/7.0);
    
    // Make a temporary destination path if necessary
    // If we want to apply file system compression after we're done applying, we'll need to use a different
    // temporary path
    NSString *destination;
    if (header.fileSystemCompression) {
        destination = [finalDestination.stringByDeletingLastPathComponent stringByAppendingPathComponent:[NSString stringWithFormat:@".tmp.%@", finalDestination.lastPathComponent]];
    } else {
        destination = finalDestination;
    }

    if (!removeTree(destination)) {
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to remove %@", destination] }];
        }
        return NO;
    }

    progressCallback(3/7.0);

    NSFileManager *fileManager = [[NSFileManager alloc] init];
    
    if (!copyTree(fileManager, source, destination)) {
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to copy %@ to %@", source, destination] }];
        }
        return NO;
    }
    
    // Preserve file creation date only for the root item if the date is recorded
    // (requires major version 4 or later)
    NSDate *bundleCreationDate = header.bundleCreationDate;
    if (bundleCreationDate != nil) {
        NSError *setFileCreationDateError = nil;
        if (![fileManager setAttributes:@{NSFileCreationDate: bundleCreationDate} ofItemAtPath:destination error:&setFileCreationDateError]) {
            fprintf(stderr, "\nWarning: failed to set file creation date: %s", setFileCreationDateError.localizedDescription.UTF8String);
        }
    }

    progressCallback(4/7.0);

    if (verbose) {
        fprintf(stderr, "\nPatching...");
    }
    
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

        if ((commands & SPUDeltaItemCommandClone) != 0 && (commands & SPUDeltaItemCommandBinaryDiff) == 0) {
            NSString *clonedRelativePath = item.clonedRelativePath;
            if ([clonedRelativePath.pathComponents containsObject:@".."]) {
                if (error != NULL) {
                    *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Relative path for clone '%@' contains '..' path component", clonedRelativePath] }];
                }
                *stop = YES;
                return;
            }
            
            NSString *clonedOriginalPath = [source stringByAppendingPathComponent:clonedRelativePath];
            
            // Ensure there isn't an item already at our destination
            [fileManager removeItemAtPath:destinationFilePath error:NULL];
            
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
            item.itemFilePath = tempDiffFile;
            
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
            
            NSString *sourceDiffFilePath;
            NSString *clonedRelativePath;
            if ((commands & SPUDeltaItemCommandClone) != 0) {
                clonedRelativePath = item.clonedRelativePath;
                if ([clonedRelativePath.pathComponents containsObject:@".."]) {
                    if (error != NULL) {
                        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Relative path for clone '%@' contains '..' path component", clonedRelativePath] }];
                    }
                    *stop = YES;
                    return;
                }
                
                sourceDiffFilePath = [source stringByAppendingPathComponent:clonedRelativePath];
            } else {
                sourceDiffFilePath = sourceFilePath;
                clonedRelativePath = nil;
            }
            
            // Decide if we need to preserve original file permissions from the original file
            // applyBinaryDeltaToFile() normally preserves file permissions on the file it's replacing.
            // However this is not possible if the destination file we're patching is not writable.
            // We also need to preserve permissions for clones except when we'll be changing permissions later anyway.
            BOOL needsToCopyFilePermissions;
            if (![fileManager isWritableFileAtPath:destinationFilePath]) {
                // Remove the file non-writable we're patching that may cause issues
                [fileManager removeItemAtPath:destinationFilePath error:NULL];
                
                // We will need to preserve permissions if there is no need to make permission changes later on
                needsToCopyFilePermissions = (commands & SPUDeltaItemCommandModifyPermissions) == 0;
            } else {
                needsToCopyFilePermissions = ((commands & SPUDeltaItemCommandClone) != 0) && ((commands & SPUDeltaItemCommandModifyPermissions) == 0);
            }
            
            if (!applyBinaryDeltaToFile(tempDiffFile, sourceDiffFilePath, destinationFilePath)) {
                if (verbose) {
                    fprintf(stderr, "\n");
                }
                if (error != NULL) {
                    *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to patch %@ to destination %@", sourceFilePath, destinationFilePath] }];
                }
                *stop = YES;
                return;
            }
            
            if (needsToCopyFilePermissions) {
                struct stat sourceFileInfo = {0};
                if (lstat(sourceDiffFilePath.fileSystemRepresentation, &sourceFileInfo) != 0) {
                    if (verbose) {
                        fprintf(stderr, "\n");
                    }
                    if (error != NULL) {
                        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to retrieve stat info from %@", sourceFilePath] }];
                    }
                    *stop = YES;
                    return;
                }
                
                if (chmod(destinationFilePath.fileSystemRepresentation, sourceFileInfo.st_mode) != 0) {
                    if (verbose) {
                        fprintf(stderr, "\n");
                    }
                    if (error != NULL) {
                        *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteNoPermissionError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to modify permissions (%u) on file %@", sourceFileInfo.st_mode, destinationFilePath] }];
                    }
                    *stop = YES;
                    return;
                }
            }

            if (verbose) {
                if ((commands & SPUDeltaItemCommandClone) != 0) {
                    fprintf(stderr, "\n🔨  %s %s -> %s", VERBOSE_PATCHED, [clonedRelativePath fileSystemRepresentation], [relativePath fileSystemRepresentation]);
                } else {
                    fprintf(stderr, "\n🔨  %s %s", VERBOSE_PATCHED, [relativePath fileSystemRepresentation]);
                }
            }
        } else if ((commands & SPUDeltaItemCommandExtract) != 0) { // extract and permission modifications don't coexist
            item.itemFilePath = destinationFilePath;
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
            mode_t mode = (mode_t)item.mode;
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
                fprintf(stderr, "\n👮  %s %s (0%o)", VERBOSE_MODIFIED, [relativePath fileSystemRepresentation], (unsigned int)(mode & PERMISSION_FLAGS));
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
        removeTree(destination);
        return NO;
    }

    progressCallback(5/7.0);
    
    // Re-apply file system compression is requested
    if (header.fileSystemCompression) {
        if (verbose) {
            fprintf(stderr, "\nApplying file system compression...");
        }
        
        NSTask *dittoTask = [[NSTask alloc] init];
        
        dittoTask.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto" isDirectory:NO];
        dittoTask.arguments = @[@"--hfsCompression", destination, finalDestination];
        
        // If we fail to apply file system compression, we will try falling back to not doing this
        BOOL failedToApplyFileSystemCompression = NO;
        
        NSError *launchError = nil;
        if (![dittoTask launchAndReturnError:&launchError]) {
            failedToApplyFileSystemCompression = YES;
            
            fprintf(stderr, "\nWarning: failed to launch ditto task for file compression: %s", launchError.localizedDescription.UTF8String);
        }
        
        if (!failedToApplyFileSystemCompression) {
            [dittoTask waitUntilExit];
            
            if (dittoTask.terminationStatus != 0) {
                failedToApplyFileSystemCompression = YES;
                
                fprintf(stderr, "\nWarning: ditto task for file compression returned exit status %d", dittoTask.terminationStatus);
            }
        }
        
        if (failedToApplyFileSystemCompression) {
            // Try to replace bundle normally
            if (![fileManager replaceItemAtURL:[NSURL fileURLWithPath:finalDestination] withItemAtURL:[NSURL fileURLWithPath:destination isDirectory:YES] backupItemName:nil options:0 resultingItemURL:NULL error:error]) {
                removeTree(destination);
                return NO;
            }
        } else {
            // Remove original copy
            [fileManager removeItemAtURL:[NSURL fileURLWithPath:destination isDirectory:YES] error:NULL];
        }
    }
    
    progressCallback(6/7.0);
    
    if (verbose) {
        fprintf(stderr, "\nVerifying destination...");
    }
    
    unsigned char afterHash[BINARY_DELTA_HASH_LENGTH] = {0};
    if (!getRawHashOfTreeWithVersion(afterHash, finalDestination, majorDiffVersion)) {
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Unable to calculate hash of tree %@", finalDestination] }];
        }
        removeTree(finalDestination);
        return NO;
    }
    
    if (memcmp(afterHash, expectedAfterHash, BINARY_DELTA_HASH_LENGTH) != 0) {
        if (verbose) {
            fprintf(stderr, "\n");
        }
        if (error != NULL) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Destination doesn't have expected hash (%@ != %@).  Giving up.", displayHashFromRawHash(expectedAfterHash), displayHashFromRawHash(afterHash)] }];
        }
        removeTree(finalDestination);
        return NO;
    }

    progressCallback(7/7.0);

    if (verbose) {
        fprintf(stderr, "\nDone!\n");
    }
    return YES;
}
