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
	
	NSString* openCommand = @"/usr/bin/open";
	if ([[NSFileManager defaultManager] fileExistsAtPath:openCommand])
	{
		// Using "open" insures that the installer application is brought to the front.
		// The -W and -n options were added to the 'open' command in 10.5
		// -W = wait until the app has quit.  -n = Open another instance if already open.
		// -b = app bundle identifier
		NSArray *args = [NSArray arrayWithObjects:@"-W", @"-n", @"-b", @"com.apple.installer", path, nil];
		NSTask *openTask = [NSTask launchedTaskWithLaunchPath:openCommand arguments:args];
		[openTask waitUntilExit];
	}
	else
	{
		error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUMissingInstallerToolError userInfo:[NSDictionary dictionaryWithObject:@"Couldn't find Apple's installer tool!" forKey:NSLocalizedDescriptionKey]];
		result = NO;
	}

	// Known bug: if the installation fails or is canceled, Sparkle goes ahead and restarts, thinking everything is fine.
	[self _finishInstallationWithResult:result host:host error:error delegate:delegate];
}

@end
