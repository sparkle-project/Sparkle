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
#import "SUErrors.h"
#import "SUVersionComparisonProtocol.h"
#import "SUHost.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

#warning Remove this code - it's duplicated from SUFileManager.m; probably create another file that both classes share in common
static BOOL AuthorizationExecuteWithPrivilegesAndWait(AuthorizationRef authorization, const char* executablePath, AuthorizationFlags options, char* const* arguments)
{
	sig_t oldSigChildHandler = signal(SIGCHLD, SIG_DFL);
	BOOL returnValue = YES;
	
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    // See SUFileManager.m for more details on why this deprecated function is being used
	if (AuthorizationExecuteWithPrivileges(authorization, executablePath, options, arguments, NULL) == errAuthorizationSuccess)
#pragma clang diagnostic pop
	{
		int status = 0;
		pid_t pid = wait(&status);
		if (pid == -1 || !WIFEXITED(status) || WEXITSTATUS(status) != 0)
			returnValue = NO;
	}
	else
		returnValue = NO;
	
	signal(SIGCHLD, oldSigChildHandler);
	return returnValue;
}

@implementation SUGuidedPackageInstaller (SUGuidedPackageInstallerAuthentication)

- (AuthorizationRef)authorizationForExecutable:(NSString*)executablePath
{
	SUParameterAssert(executablePath);
	
	// Get authorization using advice in Apple's Technical Q&A1172
	
	// ...create authorization without specific rights
	AuthorizationRef auth = NULL;
	OSStatus validAuth = AuthorizationCreate(NULL,
											 kAuthorizationEmptyEnvironment, 
											 kAuthorizationFlagDefaults,
											 &auth);
	// ...then extend authorization with desired rights
	if ((validAuth == errAuthorizationSuccess) &&
		(auth != NULL))
	{		
        char executableFileSystemRepresentation[PATH_MAX];
        [executablePath getFileSystemRepresentation:executableFileSystemRepresentation maxLength:sizeof(executableFileSystemRepresentation)];
		
		// Prepare a right allowing script to execute with privileges
        AuthorizationItem right = {
            .name = kAuthorizationRightExecute,
            .value = executableFileSystemRepresentation,
            .valueLength = strlen(executableFileSystemRepresentation),
        };
		
		// Package up the single right
		AuthorizationRights rights;
		memset(&rights,0,sizeof(rights));
		rights.count = 1;
		rights.items = &right;
		
		// Extend rights to run script
		validAuth = AuthorizationCopyRights(auth,
											&rights,
											kAuthorizationEmptyEnvironment,
                                            (AuthorizationFlags)
											(kAuthorizationFlagPreAuthorize |
											kAuthorizationFlagExtendRights |
											kAuthorizationFlagInteractionAllowed),
											NULL);
		if (validAuth != errAuthorizationSuccess)
		{
			// Error, clean up authorization
			(void) AuthorizationFree(auth,kAuthorizationFlagDefaults);
			auth = NULL;
		}
	}
	
	return auth;
}

@end

@interface SUGuidedPackageInstaller ()

@property (nonatomic, readonly, copy) NSString *packagePath;

@end

@implementation SUGuidedPackageInstaller

@synthesize packagePath = _packagePath;

- (instancetype)initWithHost:(SUHost *)__unused host sourcePath:(NSString *)sourcePath installationPath:(NSString *)__unused installationPath versionComparator:(id <SUVersionComparison>)__unused comparator
{
    self = [super init];
    if (self != nil) {
        _packagePath = [sourcePath copy];
    }
    return self;
}

- (BOOL)startInstallation:(NSError * __autoreleasing *)__unused error
{
    return YES;
}

- (BOOL)resumeInstallation:(NSError * __autoreleasing *)error
{
    // Preflight
    NSString* installerPath = @"/usr/sbin/installer"; // Mac OS X 10.2+ command line installer tool
    
    // Create authorization for installer executable
    NSString *errorMessage = nil;
    BOOL validInstallation = NO;
    AuthorizationRef auth = [self authorizationForExecutable:installerPath];
    if (auth != NULL)
    {
        char pathBuffer[PATH_MAX] = {0};
        [self.packagePath getFileSystemRepresentation:pathBuffer maxLength:sizeof(pathBuffer)];
        
        // Permission was granted to execute the installer with privileges
        char * const arguments[] = {
            "-pkg",
            pathBuffer,
            "-target",
            "/",
            NULL
        };
        validInstallation = AuthorizationExecuteWithPrivilegesAndWait(auth,
                                                                      [installerPath fileSystemRepresentation],
                                                                      kAuthorizationFlagDefaults,
                                                                      arguments);
        // TODO: wait for communications pipe to close via fileno & CFSocketCreateWithNative
        AuthorizationFree(auth,kAuthorizationFlagDefaults);
        
        if (!validInstallation) {
            errorMessage = @"Sparkle Updater: Script authorization denied.";
        }
    }
    else
    {
        errorMessage = @"Sparkle Updater: Script authorization reference failed to be created.";
    }
    if (!validInstallation && error != NULL) {
        *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
    }
    return validInstallation;
}

- (void)cleanup
{
}

@end
