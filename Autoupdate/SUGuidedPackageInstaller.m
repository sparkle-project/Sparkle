//
//  SUGuidedPackageInstaller.m
//  Sparkle
//
//  Created by Graham Miln on 14/05/2010.
//  Copyright 2010 Dragon Systems Software Limited. All rights reserved.
//

#import <sys/stat.h>
#import "SUGuidedPackageInstaller.h"
#import "SUErrors.h"


#include "AppKitPrevention.h"

@interface SUGuidedPackageInstaller ()

@property (nonatomic, readonly, copy) NSString *packagePath;
@property (nonatomic, readonly, copy) NSString *installationPath;

@end

@implementation SUGuidedPackageInstaller

@synthesize packagePath = _packagePath;
@synthesize installationPath = _installationPath;

- (instancetype)initWithPackagePath:(NSString *)packagePath installationPath:(NSString *)installationPath
{
    self = [super init];
    if (self != nil) {
        _packagePath = [packagePath copy];
        _installationPath = [installationPath copy];
    }
    return self;
}

- (BOOL)performInitialInstallation:(NSError * __autoreleasing *)__unused error
{
    return YES;
}

- (BOOL)performFinalInstallation:(NSError * __autoreleasing *)error
{
    // This command *must* be run as root
    NSString *installerPath = @"/usr/sbin/installer";
    
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = installerPath;
    task.arguments = @[@"-pkg", self.packagePath, @"-target", @"/"];
    task.standardError = [NSPipe pipe];
    task.standardOutput = [NSPipe pipe];
    
    BOOL success = YES;
    @try {
        [task launch];
        [task waitUntilExit];
        if (task.terminationStatus != EXIT_SUCCESS) {
            success = NO;
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Guided package installer returned non-zero exit status (%d)", task.terminationStatus] }];
            }
        }
    } @catch (NSException *) {
        success = NO;
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Guided package installer task threw an exception"] }];
        }
    }
    return success;
}

- (BOOL)canInstallSilently
{
    return YES;
}

@end
