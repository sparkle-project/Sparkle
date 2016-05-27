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

- (BOOL)performSecondStageAllowingAuthorization:(BOOL)allowsAuthorization withEnvironment:(SUAuthorizationEnvironment * _Nullable)authorizationEnvironment allowingUI:(BOOL)allowsUI error:(NSError * __autoreleasing *)error
{
    if (!allowsUI) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{NSLocalizedDescriptionKey : @"Guided installer cannot continue if showing UI is not allowed"}];
        }
        return NO;
    }
    
    // If we're root, we can allow using the authorization APIs
    self.fileManager = (allowsAuthorization || (geteuid() == 0)) ? [SUFileManager fileManagerAllowingAuthorizationWithEnvironment:authorizationEnvironment] : [SUFileManager fileManager];
    
    return [self.fileManager grantAuthorizationPrivilegesWithError:error];
}

- (BOOL)performThirdStage:(NSError * __autoreleasing *)error
{
    BOOL validInstallation = NO;
    
    char pathBuffer[PATH_MAX] = {0};
    if (![self.packagePath getFileSystemRepresentation:pathBuffer maxLength:sizeof(pathBuffer)]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{NSLocalizedDescriptionKey : @"Failed to get file system representation of package path"}];
        }
        return NO;
    }
    
    const char *installerPath = "/usr/sbin/installer"; // Mac OS X 10.2+ command line installer tool
    char * const arguments[] = {
        "-pkg",
        pathBuffer,
        "-target",
        "/",
        NULL
    };
    
    validInstallation = [self.fileManager authorizeAndExecuteWithPrivilegesAtPath:installerPath arguments:arguments];
    
    if (!validInstallation && error != NULL) {
        *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{NSLocalizedDescriptionKey : @"Failed to authorize installer"}];
    }
    return validInstallation;
}

- (BOOL)displaysUserProgress
{
    return NO;
}

- (BOOL)canInstallSilently
{
    return ![self mayNeedToRequestAuthorization];
}

- (BOOL)mayNeedToRequestAuthorization
{
    return YES;
}

- (void)cleanup
{
}

@end
