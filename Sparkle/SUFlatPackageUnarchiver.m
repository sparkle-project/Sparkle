//
//  SUFlatPackageUnarchiver.m
//  Autoupdate
//
//  Created by Mayur Pawashe on 1/30/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SUFlatPackageUnarchiver.h"
#import "SUUnarchiverNotifier.h"
#import "SUErrors.h"


#include "AppKitPrevention.h"

@interface SUFlatPackageUnarchiver ()

@property (nonatomic, readonly) NSString *flatPackagePath;
@property (nonatomic, readonly, copy) NSString *extractionDirectory;

@end

@implementation SUFlatPackageUnarchiver

@synthesize flatPackagePath = _flatPackagePath;
@synthesize extractionDirectory = _extractionDirectory;

+ (BOOL)canUnarchivePath:(NSString *)path
{
    return [path.pathExtension isEqualToString:@"pkg"] || [path.pathExtension isEqualToString:@"mpkg"];
}

// Note in 2.x this method returns YES, but 1.x does not support pre-validation of pkgs
+ (BOOL)mustValidateBeforeExtraction
{
    return NO;
}

- (instancetype)initWithFlatPackagePath:(NSString *)flatPackagePath extractionDirectory:(NSString *)extractionDirectory
{
    self = [super init];
    if (self != nil) {
        _flatPackagePath = [flatPackagePath copy];
        _extractionDirectory = [extractionDirectory copy];
    }
    return self;
}

- (void)unarchiveWithCompletionBlock:(void (^)(NSError * _Nullable))completionBlock progressBlock:(void (^ _Nullable)(double))progressBlock
{
    SUUnarchiverNotifier *notifier = [[SUUnarchiverNotifier alloc] initWithCompletionBlock:completionBlock progressBlock:progressBlock];
    
    // Flat packages must use guided package installs, not interactive
    BOOL isDirectory = NO;
    if ([[[self.flatPackagePath stringByDeletingPathExtension] pathExtension] isEqualToString:@"sparkle_interactive"]) {
        [notifier notifyFailureWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Flat packages can not be installed interactively with 'sparkle_interactive' and must instead be guided"]}]];
    } else if (![[NSFileManager defaultManager] fileExistsAtPath:self.flatPackagePath isDirectory:&isDirectory] || isDirectory) {
        [notifier notifyFailureWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Flat package does not exist at %@", self.flatPackagePath]}]];
    } else {
        // Copying the flat package should be very fast, especially on APFS
        NSError *copyError = nil;
        if (![[NSFileManager defaultManager] copyItemAtPath:self.flatPackagePath toPath:[self.extractionDirectory stringByAppendingPathComponent:self.flatPackagePath.lastPathComponent] error:&copyError]) {
            NSMutableDictionary *userInfoDictionary = [NSMutableDictionary dictionaryWithDictionary:@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Flat package (%@) cannot be copied to extraction directory (%@)", self.flatPackagePath, self.extractionDirectory]}];
            
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

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], self.flatPackagePath]; }

@end
