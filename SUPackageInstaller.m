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
	
	NSString *installerPath = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:@"com.apple.installer"];
	installerPath = [installerPath stringByAppendingString:@"/Contents/MacOS/Installer"];
	if (![[NSFileManager defaultManager] fileExistsAtPath:installerPath])
	{
		error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUMissingInstallerToolError userInfo:[NSDictionary dictionaryWithObject:@"Couldn't find Apple's installer tool!" forKey:NSLocalizedDescriptionKey]];
		result = NO;
	}
	NSTask *installer = [NSTask launchedTaskWithLaunchPath:installerPath arguments:[NSArray arrayWithObjects:path, nil]];
	[installer waitUntilExit];
	// Known bug: if the installation fails or is canceled, Sparkle goes ahead and restarts, thinking everything is fine.
	[self _finishInstallationWithResult:result host:host error:error delegate:delegate];
}

@end
