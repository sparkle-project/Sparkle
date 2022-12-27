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
}

+ (BOOL)canUnarchivePath:(NSString *)path
{
    return [path.pathExtension isEqualToString:@"pkg"] || [path.pathExtension isEqualToString:@"mpkg"];
}

+ (BOOL)mustValidateBeforeExtraction
{
    return YES;
}

- (instancetype)initWithFlatPackagePath:(NSString *)flatPackagePath expectingInstallationType:(NSString *)installationType
{
    self = [super init];
    if (self != nil) {
        _flatPackagePath = [flatPackagePath copy];
        _expectedInstallationType = [installationType copy];
    }
    return self;
}

- (void)unarchiveWithCompletionBlock:(void (^)(NSError * _Nullable))completionBlock progressBlock:(void (^ _Nullable)(double))progressBlock
{
    SUUnarchiverNotifier *notifier = [[SUUnarchiverNotifier alloc] initWithCompletionBlock:completionBlock progressBlock:progressBlock];
    
    // Flat packages must use guided package installs, not interactive
    BOOL isDirectory = NO;
    if (![_expectedInstallationType isEqualToString:SPUInstallationTypeGuidedPackage]) {
        [notifier notifyFailureWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Flat package does not have guided installation type but %@ instead", _expectedInstallationType]}]];
    } else if (![[NSFileManager defaultManager] fileExistsAtPath:_flatPackagePath isDirectory:&isDirectory] || isDirectory) {
        [notifier notifyFailureWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Flat package does not exist at %@", _flatPackagePath]}]];
    } else {
        [notifier notifyProgress:1.0];
        [notifier notifySuccess];
    }
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], _flatPackagePath]; }

@end

#endif
