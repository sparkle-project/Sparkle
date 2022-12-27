//
//  SUGuidedPackageInstaller.m
//  Sparkle
//
//  Created by Graham Miln on 14/05/2010.
//  Copyright 2010 Dragon Systems Software Limited. All rights reserved.
//

#if SPARKLE_BUILD_PACKAGE_SUPPORT

#import <sys/stat.h>
#import "SUGuidedPackageInstaller.h"
#import "SUErrors.h"


#include "AppKitPrevention.h"

@implementation SUGuidedPackageInstaller
{
    NSString *_packagePath;
    NSString *_homeDirectory;
    NSString *_userName;
}

- (instancetype)initWithPackagePath:(NSString *)packagePath homeDirectory:(NSString *)homeDirectory userName:(NSString *)userName
{
    self = [super init];
    if (self != nil) {
        _packagePath = [packagePath copy];
        _homeDirectory = [homeDirectory copy];
        _userName = [userName copy];
    }
    return self;
}

- (BOOL)performInitialInstallation:(NSError * __autoreleasing *)__unused error
{
    return YES;
}

- (BOOL)performFinalInstallationProgressBlock:(nullable void(^)(double))__unused cb error:(NSError * __autoreleasing *)error
{
    // This command *must* be run as root
    NSString *installerPath = @"/usr/sbin/installer";
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = installerPath;
    task.arguments = @[@"-pkg", _packagePath, @"-target", @"/"];
    // Set the $HOME and $USER variables so pre/post install scripts reference the correct user environment
    task.environment = @{@"HOME": _homeDirectory, @"USER": _userName};
    task.standardError = nil;
    task.standardOutput = nil;
    
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (error != NULL) {
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{ NSLocalizedDescriptionKey: @"Guided package installer failed to launch" }];
            
            if (launchError != nil) {
                userInfo[NSUnderlyingErrorKey] = launchError;
            }
            
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:userInfo];
        }
        return NO;
    }
    
    [task waitUntilExit];
    
    if (task.terminationStatus != EXIT_SUCCESS) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Guided package installer returned non-zero exit status (%d)", task.terminationStatus] }];
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
    return YES;
}

@end

#endif
