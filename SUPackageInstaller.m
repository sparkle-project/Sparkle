//
//  SUPackageInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPackageInstaller.h"
#import <Cocoa/Cocoa.h>
#import "SUConstants.h"

NSString *SUPackageInstallerCommandKey = @"SUPackageInstallerCommand";
NSString *SUPackageInstallerArgumentsKey = @"SUPackageInstallerArguments";
NSString *SUPackageInstallerHostKey = @"SUPackageInstallerHost";
NSString *SUPackageInstallerDelegateKey = @"SUPackageInstallerDelegate";
NSString *SUPackageInstallerInstallationPathKey = @"SUPackageInstallerInstallationPathKey";

@implementation SUPackageInstaller

+ (void)finishInstallationWithInfo:(NSDictionary *)info
{
	[self finishInstallationToPath:[info objectForKey:SUPackageInstallerInstallationPathKey] withResult:YES host:[info objectForKey:SUPackageInstallerHostKey] error:nil delegate:[info objectForKey:SUPackageInstallerDelegateKey]];
}

+ (void)performInstallationWithInfo:(NSDictionary *)info
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	
	NSTask *installer = [NSTask launchedTaskWithLaunchPath:[info objectForKey:SUPackageInstallerCommandKey] arguments:[info objectForKey:SUPackageInstallerArgumentsKey]];
	[installer waitUntilExit];
	
	// Known bug: if the installation fails or is canceled, Sparkle goes ahead and restarts, thinking everything is fine.
	[self performSelectorOnMainThread:@selector(finishInstallationWithInfo:) withObject:info waitUntilDone:NO];
	
	[pool drain];
}

+ (void)performInstallationToPath:(NSString *)installationPath fromPath:(NSString *)path host:(SUHost *)host delegate:delegate synchronously:(BOOL)synchronously versionComparator:(id <SUVersionComparison>)comparator
{
	NSString *command;
	NSArray *args;
	
	if (floor(NSAppKitVersionNumber) == NSAppKitVersionNumber10_4) {
		// 10.4 uses Installer.app because the "open" command in 10.4 doesn't support -W and -n
		command = [[NSBundle bundleWithIdentifier:@"com.apple.installer"] executablePath];
		args = [NSArray arrayWithObjects:path, nil];
	} else {
		// 10.5 and later. Run installer using the "open" command to ensure it is launched in front of current application.
		// The -W and -n options were added to the 'open' command in 10.5
		// -W = wait until the app has quit.
		// -n = Open another instance if already open.
		// -b = app bundle identifier
		command = @"/usr/bin/open";
		args = [NSArray arrayWithObjects:@"-W", @"-n", @"-b", @"com.apple.installer", path, nil];
	}
	if (![[NSFileManager defaultManager] fileExistsAtPath:command])
	{
		NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUMissingInstallerToolError userInfo:[NSDictionary dictionaryWithObject:@"Couldn't find Apple's installer tool!" forKey:NSLocalizedDescriptionKey]];
		[self finishInstallationToPath:installationPath withResult:NO host:host error:error delegate:delegate];
	}
	else 
	{
		NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys:command, SUPackageInstallerCommandKey, args, SUPackageInstallerArgumentsKey, host, SUPackageInstallerHostKey, delegate, SUPackageInstallerDelegateKey, installationPath, SUPackageInstallerInstallationPathKey, nil];
		if (synchronously)
			[self performInstallationWithInfo:info];
		else
			[NSThread detachNewThreadSelector:@selector(performInstallationWithInfo:) toTarget:self withObject:info];
	}
}

@end
