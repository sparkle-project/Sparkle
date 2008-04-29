//
//  SUPlainInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPlainInstaller.h"


@implementation SUPlainInstaller

+ (void)installPath:(NSString *)path overHostBundle:(NSBundle *)bundle delegate:delegate
{
	NSError *error;
	BOOL result = [[NSFileManager defaultManager] copyPathWithAuthentication:path overPath:[bundle bundlePath] error:&error];
	[self _finishInstallationWithResult:result hostBundle:bundle error:error delegate:delegate];
}

+ (void)performInstallationWithInfo:(NSDictionary *)info
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	[self installPath:[info objectForKey:SUInstallerPathKey] overHostBundle:[info objectForKey:SUInstallerHostBundleKey] delegate:[info objectForKey:SUInstallerDelegateKey]];
	
	[pool release];
}

@end
