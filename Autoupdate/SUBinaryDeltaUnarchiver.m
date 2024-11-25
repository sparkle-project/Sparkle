//
//  SUBinaryDeltaUnarchiver.m
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-03.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#import "SUBinaryDeltaUnarchiver.h"
#import "SUUnarchiverNotifier.h"
#import "SUBinaryDeltaCommon.h"
#import "SUBinaryDeltaApply.h"
#import "SULog.h"
#import "SUFileManager.h"


#include "AppKitPrevention.h"

@implementation SUBinaryDeltaUnarchiver
{
    NSString *_archivePath;
    NSString *_updateHostBundlePath;
    NSString *_extractionDirectory;
}

+ (BOOL)canUnarchivePath:(NSString *)path
{
    return [[path pathExtension] isEqualToString:@"delta"];
}

+ (BOOL)mustValidateBeforeExtraction
{
    return YES;
}

// According to https://developer.apple.com/library/mac/documentation/Carbon/Conceptual/MDImporters/Concepts/Troubleshooting.html
// We should make sure mdimporter bundles have an up to date time in the event they were delta updated.
// We used to invoke mdimport on the bundle but this is not a very good approach.
// There's no need to do that for non-delta updates and for updates that contain no mdimporters.
// Moreover, updating the timestamp on the mdimporter bundles is what developers have to do anyway when shipping their new update outside of Sparkle
// Note: this is used from unit tests
+ (void)updateSpotlightImportersAtBundlePath:(NSString *)targetPath
#ifndef BUILDING_SPARKLE_TESTS
SPU_OBJC_DIRECT
#endif
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
        
        SUFileManager *fileManager = [[SUFileManager alloc] init];
        for (NSURL *file in filesToUpdate) {
            NSError *error = nil;
            if (![fileManager updateModificationAndAccessTimeOfItemAtURL:file error:&error]) {
                SULog(SULogLevelError, @"Error: During delta unarchiving, failed to touch %@", error);
            }
        }
    }
}

- (instancetype)initWithArchivePath:(NSString *)archivePath extractionDirectory:(NSString *)extractionDirectory updateHostBundlePath:(NSString *)updateHostBundlePath
{
    self = [super init];
    if (self != nil) {
        _archivePath = [archivePath copy];
        _updateHostBundlePath = [updateHostBundlePath copy];
        _extractionDirectory = [extractionDirectory copy];
    }
    return self;
}

- (BOOL)needsVerifyBeforeExtractionKey
{
    return NO;
}

- (void)unarchiveWithCompletionBlock:(void (^)(NSError * _Nullable))completionBlock progressBlock:(void (^ _Nullable)(double))progressBlock waitForCleanup:(BOOL)__unused waitForCleanup
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            SUUnarchiverNotifier *notifier = [[SUUnarchiverNotifier alloc] initWithCompletionBlock:completionBlock progressBlock:progressBlock];
            [self extractDeltaWithNotifier:notifier];
        }
    });
}

- (void)extractDeltaWithNotifier:(SUUnarchiverNotifier *)notifier
{
    NSString *sourcePath = _updateHostBundlePath;
    NSString *targetPath = [_extractionDirectory stringByAppendingPathComponent:[sourcePath lastPathComponent]];
    
    NSError *applyDiffError = nil;
    BOOL success = applyBinaryDelta(sourcePath, targetPath, _archivePath, NO, ^(double progress){
        [notifier notifyProgress:progress];

    }, &applyDiffError);
    
    if (success) {
        [SUBinaryDeltaUnarchiver updateSpotlightImportersAtBundlePath:targetPath];
        [notifier notifySuccess];
    }
    else {
        [notifier notifyFailureWithError:applyDiffError];
    }
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], _archivePath]; }

@end
