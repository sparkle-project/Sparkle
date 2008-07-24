//
//  SUPlainInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPlainInstaller.h"
#import "SUPlainInstallerInternals.h"

extern NSString *SUInstallerPathKey;
extern NSString *SUInstallerHostKey;
extern NSString *SUInstallerDelegateKey;

@implementation SUPlainInstaller

+ (void)installPath:(NSString *)path overHost:(SUHost *)bundle delegate:delegate
{
	NSError *error;
	BOOL result = [self copyPathWithAuthentication:path overPath:[bundle bundlePath] error:&error];
	[self _finishInstallationWithResult:result host:bundle error:error delegate:delegate];
}

+ (void)_performInstallationWithInfo:(NSDictionary *)info
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	[self installPath:[info objectForKey:SUInstallerPathKey] overHost:[info objectForKey:SUInstallerHostKey] delegate:[info objectForKey:SUInstallerDelegateKey]];
	
	[pool drain];
}

+ (void)performInstallationWithPath:(NSString *)path host:(SUHost *)host delegate:delegate synchronously:(BOOL)synchronously;
{
	NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:path, SUInstallerPathKey, host, SUInstallerHostKey, delegate, SUInstallerDelegateKey, nil];
	if (synchronously)
		[self _performInstallationWithInfo:info];
	else
		[NSThread detachNewThreadSelector:@selector(_performInstallationWithInfo:) toTarget:self withObject:info];
}

@end
