//
//  SUPlainInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPlainInstaller.h"
#import "SUPlainInstallerInternals.h"

NSString *SUInstallerPathKey = @"SUInstallerPath";
NSString *SUInstallerHostKey = @"SUInstallerHost";
NSString *SUInstallerDelegateKey = @"SUInstallerDelegate";
NSString *SUInstallerVersionComparatorKey = @"SUInstallerVersionComparator";

@implementation SUPlainInstaller

+ (void)installPath:(NSString *)path overHost:(SUHost *)bundle delegate:delegate versionComparator:(id <SUVersionComparison>)comparator
{
	NSError *error;
	BOOL result = YES;

	// Prevent malicious downgrades:
	if ([comparator compareVersion:[bundle version] toVersion:[[NSBundle bundleWithPath:path] objectForInfoDictionaryKey:@"CFBundleVersion"]] == NSOrderedDescending)
	{
		NSString * errorMessage = [NSString stringWithFormat:@"Sparkle Updater: Possible attack in progress! Attempting to \"upgrade\" from %@ to %@. Aborting update.", [bundle version], [[NSBundle bundleWithPath:path] objectForInfoDictionaryKey:@"CFBundleVersion"]];
		result = NO;
		error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUDowngradeError userInfo:[NSDictionary dictionaryWithObject:errorMessage forKey:NSLocalizedDescriptionKey]];
	}
	
	if (result)
		result = [self copyPathWithAuthentication:path overPath:[bundle bundlePath] error:&error];
	[self _finishInstallationWithResult:result host:bundle error:error delegate:delegate];
}

+ (void)_performInstallationWithInfo:(NSDictionary *)info
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[self installPath:[info objectForKey:SUInstallerPathKey] overHost:[info objectForKey:SUInstallerHostKey] delegate:[info objectForKey:SUInstallerDelegateKey] versionComparator:[info objectForKey:SUInstallerVersionComparatorKey]];
	
	[pool drain];
}

+ (void)performInstallationWithPath:(NSString *)path host:(SUHost *)host delegate:delegate synchronously:(BOOL)synchronously versionComparator:(id <SUVersionComparison>)comparator
{
	NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:path, SUInstallerPathKey, host, SUInstallerHostKey, delegate, SUInstallerDelegateKey, comparator, SUInstallerVersionComparatorKey, nil];
	if (synchronously)
		[self _performInstallationWithInfo:info];
	else
		[NSThread detachNewThreadSelector:@selector(_performInstallationWithInfo:) toTarget:self withObject:info];
}

@end
