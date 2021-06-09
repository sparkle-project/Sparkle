//
//  SUPackageInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPackageInstaller.h"
#import "SUConstants.h"
#import "SUErrors.h"
#import "SULog.h"


#include "AppKitPrevention.h"

@interface SUPackageInstaller ()

@property (nonatomic, readonly, copy) NSString *packagePath;

@end

@implementation SUPackageInstaller

static NSString *SUOpenUtilityPath = @"/usr/bin/open";

@synthesize packagePath = _packagePath;

- (instancetype)initWithPackagePath:(NSString *)packagePath
{
    self = [super init];
    if (self != nil) {
        _packagePath = [packagePath copy];
    }
    return self;
}

- (BOOL)performInitialInstallation:(NSError * __autoreleasing *)error
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:SUOpenUtilityPath]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUMissingInstallerToolError userInfo:@{ NSLocalizedDescriptionKey: @"Couldn't find Apple's installer tool!" }];
        }
        return NO;
    }
    return YES;
}

- (BOOL)performFinalInstallationProgressBlock:(nullable void(^)(double))__unused cb error:(NSError *__autoreleasing*)error
{
    // Run installer using the "open" command to ensure it is launched in front of current application.
    // -W = wait until the app has quit.
    // -n = Open another instance if already open.
    // -b = app bundle identifier
    NSArray *args = @[@"-W", @"-n", @"-b", @"com.apple.installer", self.packagePath];
    
    // Known bug: if the installation fails or is canceled, Sparkle goes ahead and restarts, thinking everything is fine.
    @try {
        NSTask *installer = [NSTask launchedTaskWithLaunchPath:SUOpenUtilityPath arguments:args];
        [installer waitUntilExit];
    }
    @catch (NSException *exception) {
        SULog(SULogLevelError, @"Error: Failed to launch package installer: %@", exception);
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: @"Package installer failed to launch." }];
        }
        return NO;
    }
    
    return YES;
}

- (void)performCleanup
{
}

- (BOOL)canInstallSilently
{
    return NO;
}

@end
