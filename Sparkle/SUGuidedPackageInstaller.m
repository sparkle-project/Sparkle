//
//  SUGuidedPackageInstaller.m
//  Sparkle
//
//  Created by Graham Miln on 14/05/2010.
//  Copyright 2010 Dragon Systems Software Limited. All rights reserved.
//

#import <sys/stat.h>
#import <Security/Security.h>

#import "SUGuidedPackageInstaller.h"

NSString* SUInstallerGuidedInstallerFilename = @".sparkle_guide.plist"; // top level file to search for within update folder

// Constants
static NSString* SUGuidedPackageInstallerKeyGuidePath = @"SUGuidedPackageInstallerKeyGuidePath"; // NSString*
static NSString* SUGuidedPackageInstallerKeyGuide = @"SUGuidedPackageInstallerKeyGuide"; // NSDictionary*
static NSString* SUGuidedPackageInstallerKeyHost = @"SUGuidedPackageInstallerKeyHost"; // SUHost*
static NSString* SUGuidedPackageInstallerKeyDelegate = @"SUGuidedPackageInstallerKeyDelegate"; // id
static NSString* SUGuidedPackageInstallerKeyResult = @"SUGuidedPackageInstallerKeyResult"; // NSNumber[bool]
static NSString* SUGuidedPackageInstallerKeyError = @"SUGuidedPackageInstallerKeyError"; // NSError*

static NSString* SUGuidedPackageInstallerGuideKeyPackage = @"package"; // NSString*

static BOOL AuthorizationExecuteWithPrivilegesAndWait(AuthorizationRef authorization, const char* executablePath, AuthorizationFlags options, const char* const* arguments)
{
	sig_t oldSigChildHandler = signal(SIGCHLD, SIG_DFL);
	BOOL returnValue = YES;
	
    /* AuthorizationExecuteWithPrivileges used to support 10.4+; should be replaced with XPC or external process */
	if (AuthorizationExecuteWithPrivileges(authorization, executablePath, options, (char* const*)arguments, NULL) == errAuthorizationSuccess)
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

@interface SUGuidedPackageInstaller (SUGuidedPackageInstallerAuthentication)
+ (AuthorizationRef)authorizationForExecutable:(NSString*)executablePath;
@end

@interface SUGuidedPackageInstaller (SUGuidedPackageInstallerThreads)
// Perform the installation script
+ (void)performInstallationWithInfo:(NSDictionary *)theInfo;
// Complete the installation process
+ (void)finishInstallationWithInfo:(NSDictionary *)theInfo;
@end

@implementation SUGuidedPackageInstaller

// Search for and return any installer guide
+ (NSString *)installerGuideWithinUpdateFolder:(NSString *)updateFolder
{
	NSParameterAssert(updateFolder);
	
	NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:updateFolder];
	NSString *currentFile;
	while ((currentFile = [dirEnum nextObject]))
	{
		if ([[currentFile lastPathComponent] isEqualToString:SUInstallerGuidedInstallerFilename])
		{
			// Found an installer guide
			return [updateFolder stringByAppendingPathComponent:currentFile];
		}
	}
	
	// No guide found
	return nil;
}

+ (void)performInstallationToPath:(NSString *) __unused path fromPath:(NSString *)installerGuide host:(SUHost *)host delegate:delegate synchronously:(BOOL)synchronously versionComparator:(id <SUVersionComparison>) __unused comparator
{
	NSParameterAssert(installerGuide);
	NSParameterAssert(host);
	
	// Fetch the contents of the guide
	NSDictionary* guide = [NSDictionary dictionaryWithContentsOfFile:installerGuide];
	if (guide == nil)
	{
		NSString* errorMessage = [NSString stringWithFormat:@"Sparkle Updater: Installer guide contents are malformed '%@'.",installerGuide];
		NSError* error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
		[self finishInstallationToPath:installerGuide withResult:NO host:host error:error delegate:delegate];
		return;	
	}
	
	// Sanity check the contents of the guide
	if ([guide objectForKey:SUGuidedPackageInstallerGuideKeyPackage] == NO)
	{
		NSString* errorMessage = [NSString stringWithFormat:@"Sparkle Updater: Installer guide is missing '%@' entry.",SUGuidedPackageInstallerGuideKeyPackage];
		NSError* error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
		[self finishInstallationToPath:installerGuide withResult:NO host:host error:error delegate:delegate];
		return;	
	}
	
	// Package up installation details to allow for synchronous installation
	NSDictionary* info = [NSDictionary dictionaryWithObjectsAndKeys:
						  installerGuide,SUGuidedPackageInstallerKeyGuidePath,
						  guide,SUGuidedPackageInstallerKeyGuide,
						  host,SUGuidedPackageInstallerKeyHost,
						  delegate,SUGuidedPackageInstallerKeyDelegate,
						  nil];
	
	if (synchronously)
	{
		[self performInstallationWithInfo:info];
	}
	else
	{
		[NSThread detachNewThreadSelector:@selector(performInstallationWithInfo:) toTarget:self withObject:info];
	}
}

@end

@implementation SUGuidedPackageInstaller (SUGuidedPackageInstallerAuthentication)

+ (AuthorizationRef)authorizationForExecutable:(NSString*)executablePath
{
	NSParameterAssert(executablePath);
	
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
		const char* executableFileSystemRepresentation = [executablePath fileSystemRepresentation];
		
		// Prepare a right allowing script to execute with privileges
		AuthorizationItem right;
		memset(&right,0,sizeof(right));
		right.name = kAuthorizationRightExecute;
		right.value = (void*) executableFileSystemRepresentation;
		right.valueLength = strlen(executableFileSystemRepresentation);
		
		// Package up the single right
		AuthorizationRights rights;
		memset(&rights,0,sizeof(rights));
		rights.count = 1;
		rights.items = &right;
		
		// Extend rights to run script
		validAuth = AuthorizationCopyRights(auth,
											&rights,
											kAuthorizationEmptyEnvironment,
											kAuthorizationFlagPreAuthorize |
											kAuthorizationFlagExtendRights |
											kAuthorizationFlagInteractionAllowed,
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

@implementation SUGuidedPackageInstaller (SUGuidedPackageInstallerThreads)

// Perform the installation script
+ (void)performInstallationWithInfo:(NSDictionary *)theInfo
{
	NSParameterAssert(theInfo);
		
	// Preflight
	NSString* installerPath = @"/usr/sbin/installer"; // Mac OS X 10.2+ command line installer tool
	NSError* error = nil;
	
	// Check installer executable exists
	if ([[NSFileManager defaultManager] isExecutableFileAtPath:installerPath] == NO)
	{
		NSString* errorMessage = [NSString stringWithFormat:@"Sparkle Updater: Guide installer tool is missing."];
		error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
	}
	
	// Package is relative to installer guide file
	NSString* absolutePackagePath = nil;
	if (error == nil)
	{
		NSString* installerGuideParentFolderPath = [[theInfo objectForKey:SUGuidedPackageInstallerKeyGuidePath] stringByDeletingLastPathComponent];
		NSString* packagePath = [(NSDictionary*)[theInfo objectForKey:SUGuidedPackageInstallerKeyGuide] objectForKey:SUGuidedPackageInstallerGuideKeyPackage];
		NSAssert(packagePath,@"package entry is missing from guide");
		absolutePackagePath = [installerGuideParentFolderPath stringByAppendingPathComponent:packagePath];
		
		// Sanity check absolute package path exists 
		if ([[NSFileManager defaultManager] fileExistsAtPath:absolutePackagePath] == NO)
		{
			NSString* errorMessage = [NSString stringWithFormat:@"Sparkle Updater: Guide installer tool is missing."];
			error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
		}
	}
	
	// Create authorization for installer executable
	AuthorizationRef auth = nil;
	BOOL validInstallation = NO;
	if (error == nil)
	{
		auth = [self authorizationForExecutable:installerPath];
		if (auth != NULL)
		{
			// Permission was granted to execute the installer with privileges
			const char* const arguments[] = {
//				[installerPath fileSystemRepresentation],
				"-pkg",
				[absolutePackagePath fileSystemRepresentation],
				"-target",
				"/",
				NULL
			};
			validInstallation = AuthorizationExecuteWithPrivilegesAndWait(auth, 
																		  [installerPath fileSystemRepresentation],
																		  kAuthorizationFlagDefaults, 
																		  arguments);
			// TODO: wait for communications pipe to close via fileno & CFSocketCreateWithNative
		}
		else
		{
			NSString* errorMessage = [NSString stringWithFormat:@"Sparkle Updater: Script authorization denied."];
			error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
		}
	}
	
	// Release any authorization
	if (auth)
	{
		AuthorizationFree(auth,kAuthorizationFlagDefaults);
	}
	
	// Modify info to include the installation script's outcome
	NSMutableDictionary* resultInfo = [theInfo mutableCopy];
	[resultInfo setObject:[NSNumber numberWithBool:validInstallation] forKey:SUGuidedPackageInstallerKeyResult];
	if ((validInstallation == NO) &&
		(error))
	{
		[resultInfo setObject:error forKey:SUGuidedPackageInstallerKeyError];
	}
	
	[self performSelectorOnMainThread:@selector(finishInstallationWithInfo:) withObject:resultInfo waitUntilDone:NO];
}

// Complete the installation process
+ (void)finishInstallationWithInfo:(NSDictionary *)theInfo
{
	NSParameterAssert(theInfo);
	
	[self finishInstallationToPath:[theInfo objectForKey:SUGuidedPackageInstallerKeyGuidePath]
						withResult:[[theInfo objectForKey:SUGuidedPackageInstallerKeyResult] boolValue]
							  host:[theInfo objectForKey:SUGuidedPackageInstallerKeyHost]
							 error:[theInfo objectForKey:SUGuidedPackageInstallerKeyError]
						  delegate:[theInfo objectForKey:SUGuidedPackageInstallerKeyDelegate]];
}

@end
