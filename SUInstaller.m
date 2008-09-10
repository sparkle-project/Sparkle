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

@implementation SUInstaller

+ (BOOL)_isAliasFolderAtPath:(NSString *)path
{
	FSRef fileRef;
	OSStatus err = noErr;
	Boolean aliasFileFlag, folderFlag;
	NSURL *fileURL = [NSURL fileURLWithPath:path];
	
	if (FALSE == CFURLGetFSRef((CFURLRef)fileURL, &fileRef))
		err = coreFoundationUnknownErr;
	
	if (noErr == err)
		err = FSIsAliasFile(&fileRef, &aliasFileFlag, &folderFlag);
	
	if (noErr == err)
		return (BOOL)(aliasFileFlag && folderFlag);
	else
		return NO;	
}


+ (void)installFromUpdateFolder:(NSString *)updateFolder overHost:(SUHost *)host delegate:delegate synchronously:(BOOL)synchronously versionComparator:(id <SUVersionComparison>)comparator
{
	// Search subdirectories for the application
	NSString *currentFile, *newAppDownloadPath = nil, *bundleFileName = [[host bundlePath] lastPathComponent], *alternateBundleFileName = [[host name] stringByAppendingPathExtension:[[host bundlePath] pathExtension]];
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
		if ([self _isAliasFolderAtPath:currentPath] ||
			[[currentFile pathExtension] isEqualToString:[[host bundlePath] pathExtension]] ||
			[[currentFile pathExtension] isEqualToString:@"pkg"] ||
			[[currentFile pathExtension] isEqualToString:@"mpkg"])
		{
			[dirEnum skipDescendents];
		}		
	}
	
	if (newAppDownloadPath == nil)
	{
		[self _finishInstallationWithResult:NO host:host error:[NSError errorWithDomain:SUSparkleErrorDomain code:SUMissingUpdateError userInfo:[NSDictionary dictionaryWithObject:@"Couldn't find an appropriate update in the downloaded package." forKey:NSLocalizedDescriptionKey]] delegate:delegate];
	}
	else
	{
		[(isPackage ? [SUPackageInstaller class] : [SUPlainInstaller class]) performInstallationWithPath:newAppDownloadPath host:host delegate:delegate synchronously:synchronously versionComparator:comparator];
	}
}

+ (void)_mdimportHost:(SUHost *)host
{
	NSTask *mdimport = [[[NSTask alloc] init] autorelease];
	[mdimport setLaunchPath:@"/usr/bin/mdimport"];
	[mdimport setArguments:[NSArray arrayWithObject:[host bundlePath]]];
	[mdimport launch];
}

+ (void)_finishInstallationWithResult:(BOOL)result host:(SUHost *)host error:(NSError *)error delegate:delegate
{
	if (result == YES)
	{
		[self _mdimportHost:host];
		if ([delegate respondsToSelector:@selector(installerFinishedForHost:)])
			[delegate installerFinishedForHost:host];
	}
	else
	{
		if ([delegate respondsToSelector:@selector(installerForHost:failedWithError:)])
			[delegate installerForHost:host failedWithError:error];
	}		
}

@end
