//
//  SUPlainInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPlainInstaller.h"

extern NSString *SUInstallerPathKey;
extern NSString *SUInstallerHostBundleKey;
extern NSString *SUInstallerDelegateKey;

@implementation SUPlainInstaller

+ (void)installPath:(NSString *)path overHostBundle:(NSBundle *)bundle delegate:delegate
{
	NSError *error;
	BOOL result = [[NSFileManager defaultManager] copyPathWithAuthentication:path overPath:[bundle bundlePath] error:&error];
	[self _finishInstallationWithResult:result hostBundle:bundle error:error delegate:delegate];
}

+ (void)_performInstallationWithInfo:(NSDictionary *)info
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[self installPath:[info objectForKey:SUInstallerPathKey] overHostBundle:[info objectForKey:SUInstallerHostBundleKey] delegate:[info objectForKey:SUInstallerDelegateKey]];
	
	[pool drain];
}

+ (void)performInstallationWithPath:(NSString *)path hostBundle:(NSBundle *)hostBundle delegate:delegate synchronously:(BOOL)synchronously;
{
	NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:path, SUInstallerPathKey, hostBundle, SUInstallerHostBundleKey, delegate, SUInstallerDelegateKey, nil];
	if (synchronously)
		[self _performInstallationWithInfo:info];
	else
		[NSThread detachNewThreadSelector:@selector(_performInstallationWithInfo:) toTarget:self withObject:info];
}

@end
