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
