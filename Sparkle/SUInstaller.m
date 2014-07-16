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

static NSString *sUpdateFolder = nil;

+ (NSString *)updateFolder
{
    return sUpdateFolder;
}

+ (BOOL)isAliasFolderAtPath:(NSString *)path
{
    FSRef fileRef;
    OSStatus err = noErr;
    Boolean aliasFileFlag = false, folderFlag = false;
    NSURL *fileURL = [NSURL fileURLWithPath:path];

    if (FALSE == CFURLGetFSRef((CFURLRef)fileURL, &fileRef))
        err = coreFoundationUnknownErr;

    if (noErr == err)
        err = FSIsAliasFile(&fileRef, &aliasFileFlag, &folderFlag);

    if (noErr == err)
        return !!(aliasFileFlag && folderFlag);
    else
        return NO;
}

+ (NSString *)installSourcePathInUpdateFolder:(NSString *)inUpdateFolder forHost:(SUHost *)host isPackage:(BOOL *)isPackagePtr
{
    // Search subdirectories for the application
    NSString *currentFile,
        *newAppDownloadPath = nil,
        *bundleFileName = [[host bundlePath] lastPathComponent],
        *alternateBundleFileName = [[host name] stringByAppendingPathExtension:[[host bundlePath] pathExtension]];
    BOOL isPackage = NO;
    NSString *fallbackPackagePath = nil;
    NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:inUpdateFolder];

    sUpdateFolder = inUpdateFolder;

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

+ (void)installFromUpdateFolder:(NSString *)inUpdateFolder overHost:(SUHost *)host installationPath:(NSString *)installationPath delegate:(id<SUInstallerDelegate>)delegate versionComparator:(id<SUVersionComparison>)comparator
{
    BOOL isPackage = NO;
    NSString *newAppDownloadPath = [self installSourcePathInUpdateFolder:inUpdateFolder forHost:host isPackage:&isPackage];

    if (newAppDownloadPath == nil)
    {
        [self finishInstallationToPath:installationPath withResult:NO host:host error:[NSError errorWithDomain:SUSparkleErrorDomain code:SUMissingUpdateError userInfo:@{ NSLocalizedDescriptionKey: @"Couldn't find an appropriate update in the downloaded package." }] delegate:delegate];
    }
    else
    {
        [(isPackage ? [SUPackageInstaller class] : [SUPlainInstaller class])performInstallationToPath:installationPath fromPath:newAppDownloadPath host:host delegate:delegate versionComparator:comparator];
    }
}

+ (void)mdimportInstallationPath:(NSString *)installationPath
{
    // *** GETS CALLED ON NON-MAIN THREAD!

    SULog(@"mdimporting");

    NSTask *mdimport = [[NSTask alloc] init];
    [mdimport setLaunchPath:@"/usr/bin/mdimport"];
    [mdimport setArguments:@[installationPath]];
	@try
	{
        [mdimport launch];
        [mdimport waitUntilExit];
    }
    @catch (NSException *launchException)
    {
        // No big deal.
        SULog(@"Sparkle Error: %@", [launchException description]);
    }
}


#define SUNotifyDictHostKey @"SUNotifyDictHost"
#define SUNotifyDictErrorKey @"SUNotifyDictError"
#define SUNotifyDictDelegateKey @"SUNotifyDictDelegate"

+ (void)finishInstallationToPath:(NSString *)installationPath withResult:(BOOL)result host:(SUHost *)host error:(NSError *)error delegate:(id<SUInstallerDelegate>)delegate
{
	if (result)
	{
        [self mdimportInstallationPath:installationPath];
        if ([delegate respondsToSelector:@selector(installerFinishedForHost:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
				[delegate installerFinishedForHost:host];
            });
        }
	}
	else
	{
        if ([delegate respondsToSelector:@selector(installerForHost:failedWithError:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
				[delegate installerForHost:host failedWithError:error];
            });
        }
    }
}

@end
