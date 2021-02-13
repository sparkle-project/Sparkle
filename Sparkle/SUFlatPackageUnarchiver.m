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

@end

@implementation SUFlatPackageUnarchiver

@synthesize flatPackagePath = _flatPackagePath;

+ (BOOL)canUnarchivePath:(NSString *)path
{
    return [path.pathExtension isEqualToString:@"pkg"] || [path.pathExtension isEqualToString:@"mpkg"];
}

// Note in 2.x this method returns YES, but 1.x does not support pre-validation of pkgs
+ (BOOL)mustValidateBeforeExtraction
{
    return NO;
}

- (instancetype)initWithFlatPackagePath:(NSString *)flatPackagePath;
{
    self = [super init];
    if (self != nil) {
        _flatPackagePath = [flatPackagePath copy];
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
        [notifier notifyProgress:1.0];
        [notifier notifySuccess];
    }
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], self.flatPackagePath]; }

@end
