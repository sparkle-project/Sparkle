//
//  SUFlatPackageUnarchiver.m
//  Autoupdate
//
//  Created by Mayur Pawashe on 1/30/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_PACKAGE_SUPPORT

#import "SUFlatPackageUnarchiver.h"
#import "SUUnarchiverNotifier.h"
#import "SPUInstallationType.h"
#import "SUErrors.h"


#include "AppKitPrevention.h"

@implementation SUFlatPackageUnarchiver
{
    NSString *_flatPackagePath;
    NSString *_expectedInstallationType;
    NSString *_extractionDirectory;
}

+ (BOOL)canUnarchivePath:(NSString *)path
{
    return [path.pathExtension isEqualToString:@"pkg"] || [path.pathExtension isEqualToString:@"mpkg"];
}

+ (BOOL)mustValidateBeforeExtraction
{
    return YES;
}

- (instancetype)initWithFlatPackagePath:(NSString *)flatPackagePath extractionDirectory:(NSString *)extractionDirectory expectingInstallationType:(NSString *)installationType
{
    self = [super init];
    if (self != nil) {
        _flatPackagePath = [flatPackagePath copy];
        _expectedInstallationType = [installationType copy];
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
    SUUnarchiverNotifier *notifier = [[SUUnarchiverNotifier alloc] initWithCompletionBlock:completionBlock progressBlock:progressBlock];
    
    // Flat packages must use guided package installs, not interactive
    BOOL isDirectory = NO;
    if (![_expectedInstallationType isEqualToString:SPUInstallationTypeGuidedPackage]) {
        [notifier notifyFailureWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Flat package does not have guided installation type but %@ instead", _expectedInstallationType]}]];
    } else if (![[NSFileManager defaultManager] fileExistsAtPath:_flatPackagePath isDirectory:&isDirectory] || isDirectory) {
        [notifier notifyFailureWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Flat package does not exist at %@", _flatPackagePath]}]];
    } else {
        // Copying the flat package should be very fast, especially on APFS
        NSError *copyError = nil;
        if (![[NSFileManager defaultManager] copyItemAtPath:_flatPackagePath toPath:[_extractionDirectory stringByAppendingPathComponent:_flatPackagePath.lastPathComponent] error:&copyError]) {
            NSMutableDictionary *userInfoDictionary = [NSMutableDictionary dictionaryWithDictionary:@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Flat package (%@) cannot be copied to extraction directory (%@)", _flatPackagePath, _extractionDirectory]}];
            
            if (copyError != nil) {
                userInfoDictionary[NSUnderlyingErrorKey] = copyError;
            }
            
            [notifier notifyFailureWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:userInfoDictionary]];
        } else {
            [notifier notifyProgress:1.0];
            [notifier notifySuccess];
        }
    }
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], _flatPackagePath]; }

@end

#endif
