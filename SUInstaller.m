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
#import "SUHost.h"
#import "SUConstants.h"
#import "SULog.h"


@implementation SUInstaller

static NSString*	sUpdateFolder = nil;

+(NSString*)	updateFolder
{
	return sUpdateFolder;
}

+ (BOOL)isAliasFolderAtPath:(NSString *)path
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

+ (NSString *)installSourcePathInUpdateFolder:(NSString *)inUpdateFolder forHost:(SUHost *)host isPackage:(BOOL *)isPackagePtr
{
    // Search subdirectories for the application
	NSString	*currentFile,
    *newAppDownloadPath = nil,
    *bundleFileName = [[host bundlePath] lastPathComponent],
    *alternateBundleFileName = [[host name] stringByAppendingPathExtension:[[host bundlePath] pathExtension]];
	BOOL isPackage = NO;
	NSString *fallbackPackagePath = nil;
	NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath: inUpdateFolder];
	
	[sUpdateFolder release];
	sUpdateFolder = [inUpdateFolder retain];
	
	while ((currentFile = [dirEnum nextObject]))
	{
		NSString *currentPath = [inUpdateFolder stringByAppendingPathComponent:currentFile];		
		if ([[currentFile lastPathComponent] isEqualToString:bundleFileName] ||
			[[currentFile lastPathComponent] isEqualToString:alternateBundleFileName]) // We found one!
		{
			isPackage = NO;
			newAppDownloadPath = currentPath;
			break;
		}
		else if ([[currentFile pathExtension] isEqualToString:@"pkg"] ||
				 [[currentFile pathExtension] isEqualToString:@"mpkg"])
		{
			if ([[[currentFile lastPathComponent] stringByDeletingPathExtension] isEqualToString:[bundleFileName stringByDeletingPathExtension]])
			{
				isPackage = YES;
				newAppDownloadPath = currentPath;
				break;
			}
			else
			{
				// Remember any other non-matching packages we have seen should we need to use one of them as a fallback.
				fallbackPackagePath = currentPath;
			}
		}
		else
		{
			// Try matching on bundle identifiers in case the user has changed the name of the host app
			NSBundle *incomingBundle = [NSBundle bundleWithPath:currentPath];
			if(incomingBundle && [[incomingBundle bundleIdentifier] isEqualToString:[[host bundle] bundleIdentifier]])
			{
				isPackage = NO;
				newAppDownloadPath = currentPath;
				break;
			}
#if FUZZY_BUNDLE_IDENTIFIER_MATCHING
			// Try matching on the host's bundle identifier, suffixed with a single integer or a dash and a single integer.
			// e.g. this will match if the host bundle identifier is com.company.yourapp and the incoming identifier is com.company.yourapp-2 or com.company.yourapp3
			else if (incomingBundle)
			{
				// Find the root bundle identifer by stripping off trailing numbers and, if one exists, a dash
				NSRange rootBundleRange = [[[host bundle] bundleIdentifier] rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet] options:NSBackwardsSearch];
				NSString *rootBundleIdentifier = [[[host bundle] bundleIdentifier] substringToIndex:(rootBundleRange.location + 1)];
				if ([rootBundleIdentifier characterAtIndex:rootBundleRange.location] == '-') {
					rootBundleIdentifier = [rootBundleIdentifier substringToIndex:rootBundleRange.location];
				}

				// Now check to see if the incoming bundle identifer shares the same root and has a suffix that's either all numbers or a dash followed by numbers
				BOOL validIncomingBundleIdentifier = NO;
				NSRange originalBundleRange = [[incomingBundle bundleIdentifier] rangeOfString:rootBundleIdentifier options:NSAnchoredSearch];
				if (originalBundleRange.length == [[incomingBundle bundleIdentifier] length]) {
					validIncomingBundleIdentifier = YES;
				} else {
					NSString *bundleSuffix = [[incomingBundle bundleIdentifier] substringFromIndex:originalBundleRange.length];
					if ([bundleSuffix characterAtIndex:0] == '-') {
						bundleSuffix = [bundleSuffix substringFromIndex:1];
					}
					if ([bundleSuffix rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location == NSNotFound) {
						validIncomingBundleIdentifier = YES;
					}
				}
				if (validIncomingBundleIdentifier == YES) {
					isPackage = NO;
					newAppDownloadPath = currentPath;
					[host setRenamedInstallationPath:[[[host installationPath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:[currentPath lastPathComponent]]];
					break;
				}
			}
#endif
		}
		
		// Some DMGs have symlinks into /Applications! That's no good!
		if ([self isAliasFolderAtPath:currentPath])
			[dirEnum skipDescendents];
	}
	
	// We don't have a valid path. Try to use the fallback package.
    
	if (newAppDownloadPath == nil && fallbackPackagePath != nil)
	{
		isPackage = YES;
		newAppDownloadPath = fallbackPackagePath;
	}

    if (isPackagePtr) *isPackagePtr = isPackage;
    return newAppDownloadPath;
}

+ (NSString *)appPathInUpdateFolder:(NSString *)updateFolder forHost:(SUHost *)host
{
    BOOL isPackage = NO;
    NSString *path = [self installSourcePathInUpdateFolder:updateFolder forHost:host isPackage:&isPackage];
    return isPackage ? nil : path;
}

+ (void)installFromUpdateFolder:(NSString *)inUpdateFolder overHost:(SUHost *)host installationPath:(NSString *)installationPath delegate:delegate synchronously:(BOOL)synchronously versionComparator:(id <SUVersionComparison>)comparator
{
    BOOL isPackage = NO;
	NSString *finalInstallationPath = installationPath;
	NSString *newAppDownloadPath = [self installSourcePathInUpdateFolder:inUpdateFolder forHost:host isPackage:&isPackage];
#if FUZZY_BUNDLE_IDENTIFIER_MATCHING
	if (![[[host bundlePath] lastPathComponent] isEqualToString:[newAppDownloadPath lastPathComponent]]) {
		finalInstallationPath = [[installationPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:[newAppDownloadPath lastPathComponent]];
		[host setRenamedInstallationPath:finalInstallationPath];
	}
#endif
    
	if (newAppDownloadPath == nil)
	{
		[self finishInstallationToPath:installationPath withResult:NO host:host error:[NSError errorWithDomain:SUSparkleErrorDomain code:SUMissingUpdateError userInfo:[NSDictionary dictionaryWithObject:@"Couldn't find an appropriate update in the downloaded package." forKey:NSLocalizedDescriptionKey]] delegate:delegate];
	}
	else
	{
		[(isPackage ? [SUPackageInstaller class] : [SUPlainInstaller class]) performInstallationToPath:finalInstallationPath fromPath:newAppDownloadPath host:host delegate:delegate synchronously:synchronously versionComparator:comparator];
	}
}

+ (void)mdimportInstallationPath:(NSString *)installationPath
{
	// *** GETS CALLED ON NON-MAIN THREAD!
	
	SULog( @"mdimporting" );
	
	NSTask *mdimport = [[[NSTask alloc] init] autorelease];
	[mdimport setLaunchPath:@"/usr/bin/mdimport"];
	[mdimport setArguments:[NSArray arrayWithObject:installationPath]];
	@try
	{
		[mdimport launch];
		[mdimport waitUntilExit];
	}
	@catch (NSException * launchException)
	{
		// No big deal.
		SULog(@"Sparkle Error: %@", [launchException description]);
	}
}


#define		SUNotifyDictHostKey		@"SUNotifyDictHost"
#define		SUNotifyDictErrorKey	@"SUNotifyDictError"
#define		SUNotifyDictDelegateKey	@"SUNotifyDictDelegate"

+ (void)finishInstallationToPath:(NSString *)installationPath withResult:(BOOL)result host:(SUHost *)host error:(NSError *)error delegate:delegate
{
	if (result)
	{
		[self mdimportInstallationPath:installationPath];
		if ([delegate respondsToSelector:@selector(installerFinishedForHost:)])
			[delegate performSelectorOnMainThread: @selector(installerFinishedForHost:) withObject: host waitUntilDone: NO];
	}
	else
	{
		if ([delegate respondsToSelector:@selector(installerForHost:failedWithError:)])
			[self performSelectorOnMainThread: @selector(notifyDelegateOfFailure:) withObject: [NSDictionary dictionaryWithObjectsAndKeys: host, SUNotifyDictHostKey, error, SUNotifyDictErrorKey, delegate, SUNotifyDictDelegateKey, nil] waitUntilDone: NO];
	}		
}


+(void)	notifyDelegateOfFailure: (NSDictionary*)dict
{
	[[dict objectForKey: SUNotifyDictDelegateKey] installerForHost: [dict objectForKey: SUNotifyDictHostKey] failedWithError: [dict objectForKey: SUNotifyDictErrorKey]];
}

@end
