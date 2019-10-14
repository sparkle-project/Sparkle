//
//  SUGuidedPackageInstaller.m
//  Sparkle
//
//  Created by Graham Miln on 14/05/2010.
//  Copyright 2010 Dragon Systems Software Limited. All rights reserved.
//

#import "SUGuidedPackageInstaller.h"
#import "SUFileManager.h"


#include "AppKitPrevention.h"

@interface SUGuidedPackageInstaller ()

@property (nonatomic, readonly, copy) NSString *packagePath;
@property (nonatomic, readonly, copy) NSString *installationPath;
@property (nonatomic, readonly, copy) NSString *fileOperationToolPath;

@end

@implementation SUGuidedPackageInstaller

@synthesize packagePath = _packagePath;
@synthesize installationPath = _installationPath;
@synthesize fileOperationToolPath = _fileOperationToolPath;

- (instancetype)initWithPackagePath:(NSString *)packagePath installationPath:(NSString *)installationPath fileOperationToolPath:(NSString *)fileOperationToolPath
{
    self = [super init];
    if (self != nil) {
        _packagePath = [packagePath copy];
        _installationPath = [installationPath copy];
        _fileOperationToolPath = [fileOperationToolPath copy];
    }
    return self;
}

- (BOOL)performInitialInstallation:(NSError * __autoreleasing *)__unused error
{
    return YES;
}

- (BOOL)performFinalInstallationProgressBlock:(nullable void(^)(double))progressBlock error:(NSError * __autoreleasing *)error
{
    SUFileManager *fileManager = [SUFileManager fileManagerWithAuthorizationToolPath:self.fileOperationToolPath];
    
    return [fileManager executePackageAtURL:[NSURL fileURLWithPath:self.packagePath] progressBlock:progressBlock error:error];
}

- (BOOL)canInstallSilently
{
    return YES;
}

@end
