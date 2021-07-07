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
@property (nonatomic, readonly, copy) NSString *homeDirectory;
@property (nonatomic, readonly, copy) NSString *userName;

@end

@implementation SUGuidedPackageInstaller

@synthesize packagePath = _packagePath;
@synthesize homeDirectory = _homeDirectory;
@synthesize userName = _userName;

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
    task.arguments = @[@"-pkg", self.packagePath, @"-target", @"/"];
    // Set the $HOME and $USER variables so pre/post install scripts reference the correct user environment
    task.environment = @{@"HOME": self.homeDirectory, @"USER": self.userName};
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

- (void)performCleanup
{
}

- (BOOL)canInstallSilently
{
    return YES;
}

@end
