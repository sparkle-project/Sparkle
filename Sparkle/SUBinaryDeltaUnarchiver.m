//
//  SUBinaryDeltaUnarchiver.m
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-03.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#import "SUBinaryDeltaCommon.h"
#import "SUBinaryDeltaUnarchiver.h"
#import "SUBinaryDeltaApply.h"
#import "SUUnarchiver_Private.h"
#import "SUFileManager.h"
#import "SUHost.h"
#import "SULog.h"

@implementation SUBinaryDeltaUnarchiver

+ (BOOL)canUnarchivePath:(NSString *)path
{
    return [[path pathExtension] isEqualToString:@"delta"];
}

+ (BOOL)unsafeIfArchiveIsNotValidated
{
    return YES;
}

// According to https://developer.apple.com/library/mac/documentation/Carbon/Conceptual/MDImporters/Concepts/Troubleshooting.html
// We should make sure mdimporter bundles have an up to date time in the event they were delta updated.
// We used to invoke mdimport on the bundle but this is not a very good approach.
// There's no need to do that for non-delta updates and for updates that contain no mdimporters.
// Moreover, updating the timestamp on the mdimporter bundles is what developers have to do anyway when shipping their new update outside of Sparkle
+ (void)updateSpotlightImportersAtBundlePath:(NSString *)targetPath
{
    NSURL *targetURL = [NSURL fileURLWithPath:targetPath];
    // Only recurse if it's actually a directory.  Don't recurse into a
    // root-level symbolic link.
    NSDictionary *rootAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:targetPath error:nil];
    NSString *rootType = [rootAttributes objectForKey:NSFileType];
    
    if ([rootType isEqualToString:NSFileTypeDirectory]) {
        // The NSDirectoryEnumerator will avoid recursing into any contained
        // symbolic links, so no further type checks are needed.
        NSDirectoryEnumerator *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:targetURL includingPropertiesForKeys:nil options:(NSDirectoryEnumerationOptions)0 errorHandler:nil];
        
        NSMutableArray *filesToUpdate = [[NSMutableArray alloc] init];
        for (NSURL *file in directoryEnumerator) {
            if ([file.pathExtension isEqualToString:@"mdimporter"]) {
                [filesToUpdate addObject:file];
            }
        }
        
        SUFileManager *fileManager = [SUFileManager defaultManager];
        for (NSURL *file in filesToUpdate) {
            NSError *error = nil;
            if (![fileManager updateModificationAndAccessTimeOfItemAtURL:file error:&error]) {
                SULog(@"Error: During delta unarchiving, failed to touch %@", error);
            }
        }
    }
}

- (void)applyBinaryDelta
{
    @autoreleasepool {
        NSString *sourcePath = self.updateHostBundlePath;
        NSString *targetPath = [[self.archivePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:[sourcePath lastPathComponent]];

        NSError *applyDiffError = nil;
        BOOL success = applyBinaryDelta(sourcePath, targetPath, self.archivePath, NO, &applyDiffError);
        if (success) {
            [[self class] updateSpotlightImportersAtBundlePath:targetPath];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self notifyDelegateOfSuccess];
            });
        }
        else {
            SULog(@"Applying delta patch failed with error: %@", applyDiffError);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self notifyDelegateOfFailure];
            });
        }
    }
}

- (void)start
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self applyBinaryDelta];
    });
}

+ (void)load
{
    [self registerImplementation:self];
}

@end
