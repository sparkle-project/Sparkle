//
//  SUGuidedPackageInstaller.m
//  Sparkle
//
//  Created by Graham Miln on 14/05/2010.
//  Copyright 2010 Dragon Systems Software Limited. All rights reserved.
//

#import <sys/stat.h>
#import <Security/Security.h>
#import "SUParameterAssert.h"
#import "SUGuidedPackageInstaller.h"
#import "SUFileManager.h"
#import "SUErrors.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUGuidedPackageInstaller ()

@property (nonatomic, readonly, copy) NSString *packagePath;
@property (nonatomic) SUFileManager *fileManager;

@end

@implementation SUGuidedPackageInstaller

@synthesize packagePath = _packagePath;
@synthesize fileManager = _fileManager;

- (instancetype)initWithPackagePath:(NSString *)packagePath
{
    self = [super init];
    if (self != nil) {
        _packagePath = [packagePath copy];
    }
    return self;
}

- (BOOL)performFirstStage:(NSError * __autoreleasing *)__unused error
{
    return YES;
}

- (BOOL)performSecondStageAllowingUI:(BOOL)allowsUI error:(NSError * __autoreleasing *)error
{
    if (!allowsUI && ![self canInstallSilently]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{NSLocalizedDescriptionKey : @"Guided installer cannot continue if showing UI is not allowed"}];
        }
        return NO;
    }
    
    // If we're root, we can allow using the authorization APIs
    self.fileManager = [SUFileManager defaultManager];
    
    return YES;
}

- (BOOL)performThirdStage:(NSError * __autoreleasing *)error
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

- (BOOL)displaysUserProgress
{
    return NO;
}

- (BOOL)isRootUser
{
    return (geteuid() == 0);
}

- (BOOL)canInstallSilently
{
    return [self isRootUser];
}

- (void)cleanup
{
}

@end
