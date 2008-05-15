//
//  SUInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUInstaller.h"
#import "SUPlainInstaller.h"
#import "SUPackageInstaller.h"

NSString *SUInstallerPathKey = @"SUInstallerPath";
NSString *SUInstallerHostBundleKey = @"SUInstallerHostBundle";
NSString *SUInstallerDelegateKey = @"SUInstallerDelegate";

@implementation SUInstaller

+ (void)installFromUpdateFolder:(NSString *)updateFolder overHostBundle:(NSBundle *)hostBundle delegate:delegate synchronously:(BOOL)synchronously relauncherPath:(NSString **)relaunchPath;
{
	// Search subdirectories for the application
	NSString *currentFile, *newAppDownloadPath = nil, *bundleFileName = [[hostBundle bundlePath] lastPathComponent], *alternateBundleFileName = [[hostBundle name] stringByAppendingPathExtension:[[hostBundle bundlePath] pathExtension]];
	BOOL isPackage = NO;
	NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:updateFolder];
	while ((currentFile = [dirEnum nextObject]))
	{
		NSString *currentPath = [updateFolder stringByAppendingPathComponent:currentFile];		
		if ([[currentFile lastPathComponent] isEqualToString:bundleFileName] ||
			[[currentFile lastPathComponent] isEqualToString:alternateBundleFileName]) // We found one!
		{
			isPackage = NO;
			newAppDownloadPath = currentPath;
			break;
		}
		else if (([[currentFile pathExtension] isEqualToString:@"pkg"] || [[currentFile pathExtension] isEqualToString:@"mpkg"]) &&
				 [[[currentFile lastPathComponent] stringByDeletingPathExtension] isEqualToString:[bundleFileName stringByDeletingPathExtension]])
		{
			isPackage = YES;
			newAppDownloadPath = currentPath;
			break;
		}
		
		// Some DMGs have symlinks into /Applications! That's no good! And there's no point in looking in bundles.
		if ([[NSFileManager defaultManager] isAliasFolderAtPath:currentPath] ||
			[[currentFile pathExtension] isEqualToString:[[hostBundle bundlePath] pathExtension]] ||
			[[currentFile pathExtension] isEqualToString:@"pkg"] ||
			[[currentFile pathExtension] isEqualToString:@"mpkg"])
		{
			[dirEnum skipDescendents];
		}		
	}
	
	if (newAppDownloadPath == nil)
	{
		[self _finishInstallationWithResult:NO hostBundle:hostBundle error:[NSError errorWithDomain:SUSparkleErrorDomain code:SUMissingUpdateError userInfo:[NSDictionary dictionaryWithObject:@"Couldn't find an appropriate update in the downloaded package." forKey:NSLocalizedDescriptionKey]] delegate:delegate];
	}
	else
	{
		NSString *relaunchPathToCopy = [[NSBundle bundleForClass:[self class]]  pathForResource:@"relaunch" ofType:@""];
		NSString *targetPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[relaunchPathToCopy lastPathComponent]];
		//Only the paranoid survive: if there's already a stray copy of relaunch there, we would have problems
		[[NSFileManager defaultManager] removeFileAtPath:targetPath handler:nil];
		if([[NSFileManager defaultManager] copyPath:relaunchPathToCopy toPath:targetPath handler:nil])
			*relaunchPath = targetPath;
		
		[(isPackage ? [SUPackageInstaller class] : [SUPlainInstaller class]) performInstallationWithPath:newAppDownloadPath hostBundle:hostBundle delegate:delegate synchronously:synchronously];
	}
}

+ (void)_mdimportBundle:(NSBundle *)bundle
{
	NSTask *mdimport = [[[NSTask alloc] init] autorelease];
	[mdimport setLaunchPath:@"/usr/bin/mdimport"];
	[mdimport setArguments:[NSArray arrayWithObject:[bundle bundlePath]]];
	[mdimport launch];
}

+ (void)_finishInstallationWithResult:(BOOL)result hostBundle:(NSBundle *)hostBundle error:(NSError *)error delegate:delegate
{
	if (result == YES)
	{
		[self _mdimportBundle:hostBundle];
		if ([delegate respondsToSelector:@selector(installerFinishedForHostBundle:)])
			[delegate installerFinishedForHostBundle:hostBundle];
	}
	else
	{
		if ([delegate respondsToSelector:@selector(installerForHostBundle:failedWithError:)])
			[delegate installerForHostBundle:hostBundle failedWithError:error];
	}		
}

@end
