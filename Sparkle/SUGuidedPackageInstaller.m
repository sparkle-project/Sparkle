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
    return [self.fileManager executePackageAtURL:[NSURL fileURLWithPath:self.packagePath] error:error];
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
