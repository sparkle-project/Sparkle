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
        [notifier notifySuccess];
    }
    else {
        [notifier notifyFailureWithError:applyDiffError];
    }
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], _archivePath]; }

@end
