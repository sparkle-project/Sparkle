//
//  SUPlainInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPlainInstaller.h"
#import "SUPlainInstallerInternals.h"
#import "SUConstants.h"
#import "SUHost.h"

static NSString * const SUInstallerPathKey = @"SUInstallerPath";
static NSString * const SUInstallerTargetPathKey = @"SUInstallerTargetPath";
static NSString * const SUInstallerTempNameKey = @"SUInstallerTempName";
static NSString * const SUInstallerHostKey = @"SUInstallerHost";
static NSString * const SUInstallerDelegateKey = @"SUInstallerDelegate";
static NSString * const SUInstallerResultKey = @"SUInstallerResult";
static NSString * const SUInstallerErrorKey = @"SUInstallerError";
static NSString * const SUInstallerInstallationPathKey = @"SUInstallerInstallationPath";

@implementation SUPlainInstaller

+ (void)finishInstallationWithInfo:(NSDictionary *)info
{
	// *** GETS CALLED ON NON-MAIN THREAD!
	
	[self finishInstallationToPath:[info objectForKey:SUInstallerInstallationPathKey] withResult:[[info objectForKey:SUInstallerResultKey] boolValue] host:[info objectForKey:SUInstallerHostKey] error:[info objectForKey:SUInstallerErrorKey] delegate:[info objectForKey:SUInstallerDelegateKey]];
}

+ (void)performInstallationWithInfo:(NSDictionary *)info
{
	// *** GETS CALLED ON NON-MAIN THREAD!
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSError *error = nil;
	
	NSString	*	oldPath = [[info objectForKey:SUInstallerHostKey] bundlePath];
	NSString	*	installationPath = [info objectForKey:SUInstallerInstallationPathKey];
	BOOL result = [self copyPathWithAuthentication:[info objectForKey:SUInstallerPathKey] overPath: installationPath temporaryName:[info objectForKey:SUInstallerTempNameKey] error:&error];
	
	if( result )
	{
		BOOL	haveOld = [[NSFileManager defaultManager] fileExistsAtPath: oldPath];
		BOOL	differentFromNew = ![oldPath isEqualToString: installationPath];
		if( haveOld && differentFromNew )
			[self _movePathToTrash: oldPath];	// On success, trash old copy if there's still one due to renaming.
	}
	NSMutableDictionary *mutableInfo = [[info mutableCopy] autorelease];
	[mutableInfo setObject:[NSNumber numberWithBool:result] forKey:SUInstallerResultKey];
    [mutableInfo setObject:installationPath forKey:SUInstallerInstallationPathKey];
	if (!result && error)
		[mutableInfo setObject:error forKey:SUInstallerErrorKey];
	[self performSelectorOnMainThread:@selector(finishInstallationWithInfo:) withObject:mutableInfo waitUntilDone:NO];
    
	[pool drain];
}

+ (void)performInstallationToPath:(NSString *)installationPath fromPath:(NSString *)path host:(SUHost *)host delegate:delegate synchronously:(BOOL)synchronously versionComparator:(id <SUVersionComparison>)comparator
{
	// Prevent malicious downgrades:
	#if !PERMIT_AUTOMATED_DOWNGRADES
	if ([comparator compareVersion:[host version] toVersion:[[NSBundle bundleWithPath:path] objectForInfoDictionaryKey:@"CFBundleVersion"]] == NSOrderedDescending)
	{
		NSString * errorMessage = [NSString stringWithFormat:@"Sparkle Updater: Possible attack in progress! Attempting to \"upgrade\" from %@ to %@. Aborting update.", [host version], [[NSBundle bundleWithPath:path] objectForInfoDictionaryKey:@"CFBundleVersion"]];
		NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUDowngradeError userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
		[self finishInstallationToPath:installationPath withResult:NO host:host error:error delegate:delegate];
		return;
	}
	#endif
    
    NSString *targetPath = [host installationPath];
    NSString *tempName = [self temporaryNameForPath:targetPath];
	NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:path, SUInstallerPathKey, targetPath, SUInstallerTargetPathKey, tempName, SUInstallerTempNameKey, host, SUInstallerHostKey, delegate, SUInstallerDelegateKey, installationPath, SUInstallerInstallationPathKey, nil];
	if (synchronously)
		[self performInstallationWithInfo:info];
	else
		[NSThread detachNewThreadSelector:@selector(performInstallationWithInfo:) toTarget:self withObject:info];
}

@end
