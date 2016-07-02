//
//  SUBinaryDeltaUnarchiver.m
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-03.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#import "SUBinaryDeltaUnarchiver.h"
#import "SUBinaryDeltaCommon.h"
#import "SUBinaryDeltaApply.h"
#import "SULog.h"
#import "SUFileManager.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUBinaryDeltaUnarchiver ()

@property (nonatomic, copy, readonly) NSString *archivePath;
@property (nonatomic, copy, readonly) NSString *updateHostBundlePath;
@property (nonatomic, weak, readonly) id <SUUnarchiverDelegate> delegate;

@end

@implementation SUBinaryDeltaUnarchiver

@synthesize archivePath = _archivePath;
@synthesize updateHostBundlePath = _updateHostBundlePath;
@synthesize delegate = _delegate;

+ (BOOL)canUnarchivePath:(NSString *)path
{
    return [[path pathExtension] isEqualToString:@"delta"];
}

- (instancetype)initWithArchivePath:(NSString *)archivePath updateHostBundlePath:(NSString *)updateHostBundlePath delegate:(id <SUUnarchiverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _archivePath = [archivePath copy];
        _updateHostBundlePath = [updateHostBundlePath copy];
        _delegate = delegate;
    }
    return self;
}

- (void)start
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            NSString *sourcePath = self.updateHostBundlePath;
            NSString *targetPath = [[self.archivePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:[sourcePath lastPathComponent]];
            
            NSError *applyDiffError = nil;
            BOOL success = applyBinaryDelta(sourcePath, targetPath, self.archivePath, NO, &applyDiffError);
            
            if (success) {
                // According to https://developer.apple.com/library/mac/documentation/Carbon/Conceptual/MDImporters/Concepts/Troubleshooting.html
                // We should make sure mdimporter bundles have an up to date time in the event they were delta updated
                // We used to invoke mdimport on the bundle but this is not a very good approach because it doesn't work under root user,
                // and there's no need to do that for non-delta updates and for updates that contain no mdimporters.
                // Moreover, updating the timestamp on the mdimporter bundles is what developers have to do anyway when shipping their new update
                
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
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate unarchiverDidFinish];
                });
            }
            else {
                SULog(@"Applying delta patch failed with error: %@", applyDiffError);
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate unarchiverDidFail];
                });
            }
        }
    });
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], self.archivePath]; }

@end
