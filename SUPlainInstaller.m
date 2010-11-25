//
//  SUPlainInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPlainInstaller.h"
#import "SUPlainInstallerInternals.h"
#import "SUHost.h"

static NSString * const SUInstallerPathKey = @"SUInstallerPath";
static NSString * const SUInstallerTargetPathKey = @"SUInstallerTargetPath";
static NSString * const SUInstallerTempNameKey = @"SUInstallerTempName";
static NSString * const SUInstallerHostKey = @"SUInstallerHost";
static NSString * const SUInstallerDelegateKey = @"SUInstallerDelegate";
static NSString * const SUInstallerResultKey = @"SUInstallerResult";
static NSString * const SUInstallerErrorKey = @"SUInstallerError";

@implementation SUPlainInstaller

+ (void)finishInstallationWithInfo:(NSDictionary *)info
{
	[self finishInstallationWithResult:[[info objectForKey:SUInstallerResultKey] boolValue] host:[info objectForKey:SUInstallerHostKey] error:[info objectForKey:SUInstallerErrorKey] delegate:[info objectForKey:SUInstallerDelegateKey]];
}

+ (void)performInstallationWithInfo:(NSDictionary *)info
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSError *error = nil;
	
	BOOL result = [self copyPathWithAuthentication:[info objectForKey:SUInstallerPathKey] overPath:[info objectForKey:SUInstallerTargetPathKey] temporaryName:[info objectForKey:SUInstallerTempNameKey] error:&error];
	
	NSMutableDictionary *mutableInfo = [[info mutableCopy] autorelease];
	[mutableInfo setObject:[NSNumber numberWithBool:result] forKey:SUInstallerResultKey];
	if (!result && error)
		[mutableInfo setObject:error forKey:SUInstallerErrorKey];
	[self performSelectorOnMainThread:@selector(finishInstallationWithInfo:) withObject:mutableInfo waitUntilDone:NO];
    
	[pool drain];
}

+ (void)performInstallationWithPath:(NSString *)path host:(SUHost *)host delegate:delegate synchronously:(BOOL)synchronously versionComparator:(id <SUVersionComparison>)comparator
{
	// Prevent malicious downgrades:
	if ([comparator compareVersion:[host version] toVersion:[[NSBundle bundleWithPath:path] objectForInfoDictionaryKey:@"CFBundleVersion"]] == NSOrderedDescending)
	{
		NSString * errorMessage = [NSString stringWithFormat:@"Sparkle Updater: Possible attack in progress! Attempting to \"upgrade\" from %@ to %@. Aborting update.", [host version], [[NSBundle bundleWithPath:path] objectForInfoDictionaryKey:@"CFBundleVersion"]];
		NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUDowngradeError userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
		[self finishInstallationWithResult:NO host:host error:error delegate:delegate];
		return;
	}
    
    NSString *targetPath = [host bundlePath];
    NSString *tempName = [self temporaryNameForPath:targetPath];
	NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:path, SUInstallerPathKey, targetPath, SUInstallerTargetPathKey, tempName, SUInstallerTempNameKey, host, SUInstallerHostKey, delegate, SUInstallerDelegateKey, nil];
	if (synchronously)
		[self performInstallationWithInfo:info];
	else
		[NSThread detachNewThreadSelector:@selector(performInstallationWithInfo:) toTarget:self withObject:info];
}

@end
