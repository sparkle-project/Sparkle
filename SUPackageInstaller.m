//
//  SUPackageInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPackageInstaller.h"


@implementation SUPackageInstaller

+ (void)performInstallationWithPath:(NSString *)path host:(SUHost *)host delegate:delegate synchronously:(BOOL)synchronously versionComparator:(id <SUVersionComparison>)comparator;
{
	NSError *error = nil;
	BOOL result = YES;
	
	if (floor(NSAppKitVersionNumber) == NSAppKitVersionNumber10_4) {
		// 10.4 uses Installer.app because the "open" command in 10.4 doesn't support -W and -n
		NSString *installerPath = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:@"com.apple.installer"];
  		result = [[NSFileManager defaultManager] fileExistsAtPath:installerPath];
		if (result)
		{
			NSTask *installer = [NSTask launchedTaskWithLaunchPath:installerPath arguments:[NSArray arrayWithObjects:path, nil]];
			[installer waitUntilExit];
		}
	} else {
		// 10.5 and later. Run installer using the "open" command to ensure it is launched in front of current application.
		NSString* openCommand = @"/usr/bin/open";
		result = [[NSFileManager defaultManager] fileExistsAtPath:openCommand];
		if (result)
		{
			// The -W and -n options were added to the 'open' command in 10.5
			// -W = wait until the app has quit.
			// -n = Open another instance if already open.
			// -b = app bundle identifier
			NSArray *args = [NSArray arrayWithObjects:@"-W", @"-n", @"-b", @"com.apple.installer", path, nil];
			NSTask *openTask = [NSTask launchedTaskWithLaunchPath:openCommand arguments:args];
			[openTask waitUntilExit];
		}
	}
	
	if (!result)
	{
		error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUMissingInstallerToolError userInfo:[NSDictionary dictionaryWithObject:@"Couldn't find Apple's installer tool!" forKey:NSLocalizedDescriptionKey]];
	}
	// Known bug: if the installation fails or is canceled, Sparkle goes ahead and restarts, thinking everything is fine.
	[self _finishInstallationWithResult:result host:host error:error delegate:delegate];
}

@end
