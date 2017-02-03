//
//  SUInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUInstaller.h"
#import "SUInstallerProtocol.h"
#import "SUPlainInstaller.h"
#import "SUPackageInstaller.h"
#import "SUGuidedPackageInstaller.h"
#import "SUHost.h"
#import "SULog.h"
#import "SUErrors.h"


#include "AppKitPrevention.h"

@implementation SUInstaller

+ (BOOL)isAliasFolderAtPath:(NSString *)path
{
    NSNumber *aliasFlag = nil;
    [[NSURL fileURLWithPath:path] getResourceValue:&aliasFlag forKey:NSURLIsAliasFileKey error:nil];
    NSNumber *directoryFlag = nil;
    [[NSURL fileURLWithPath:path] getResourceValue:&directoryFlag forKey:NSURLIsDirectoryKey error:nil];
    return aliasFlag.boolValue && directoryFlag.boolValue;
}

+ (nullable NSString *)installSourcePathInUpdateFolder:(NSString *)inUpdateFolder forHost:(SUHost *)host isPackage:(BOOL *)isPackagePtr isGuided:(nullable BOOL *)isGuidedPtr
{
    NSParameterAssert(inUpdateFolder);
    NSParameterAssert(host);

    // Search subdirectories for the application
    NSString *currentFile,
        *newAppDownloadPath = nil,
        *bundleFileName = [[host bundlePath] lastPathComponent],
        *alternateBundleFileName = [[host name] stringByAppendingPathExtension:[[host bundlePath] pathExtension]];
    BOOL isPackage = NO;
    BOOL isGuided = YES;
    NSString *fallbackPackagePath = nil;
    NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:inUpdateFolder];
    NSString *bundleFileNameNoExtension = [bundleFileName stringByDeletingPathExtension];

    while ((currentFile = [dirEnum nextObject])) {
        NSString *currentPath = [inUpdateFolder stringByAppendingPathComponent:currentFile];
        NSString *currentFilename = [currentFile lastPathComponent];
        NSString *currentExtension = [currentFile pathExtension];
        NSString *currentFilenameNoExtension = [currentFilename stringByDeletingPathExtension];
        if ([currentFilename isEqualToString:bundleFileName] ||
            [currentFilename isEqualToString:alternateBundleFileName]) // We found one!
        {
            isPackage = NO;
            newAppDownloadPath = currentPath;
            break;
        } else if ([currentExtension isEqualToString:@"pkg"] ||
                   [currentExtension isEqualToString:@"mpkg"]) {
            if ([currentFilenameNoExtension isEqualToString:bundleFileNameNoExtension]) {
                isPackage = YES;
                newAppDownloadPath = currentPath;
                break;
            } else {
                // Remember any other non-matching packages we have seen should we need to use one of them as a fallback.
                fallbackPackagePath = currentPath;
            }
        } else {
            // Try matching on bundle identifiers in case the user has changed the name of the host app
            NSBundle *incomingBundle = [NSBundle bundleWithPath:currentPath];
            NSString *hostBundleIdentifier = host.bundle.bundleIdentifier;
            if (incomingBundle && [incomingBundle.bundleIdentifier isEqualToString:hostBundleIdentifier]) {
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

    if (newAppDownloadPath == nil && fallbackPackagePath != nil) {
        isPackage = YES;
        newAppDownloadPath = fallbackPackagePath;
    }

    if (isPackage) {
        // Guided (or now "normal") installs used to be opt-in (i.e, Sparkle would detect foo.sparkle_guided.pkg or foo.sparkle_guided.mpkg),
        // but to get an interactive (or "unguided") install, the developer now must opt-out of guided installations.
        
        // foo.app -> foo.sparkle_interactive.pkg or foo.sparkle_interactive.mpkg
        if ([[[newAppDownloadPath stringByDeletingPathExtension] pathExtension] isEqualToString:@"sparkle_interactive"]) {
            isGuided = NO;
        }
    }

    if (isPackagePtr)
        *isPackagePtr = isPackage;
    if (isGuidedPtr)
        *isGuidedPtr = isGuided;

    if (!newAppDownloadPath) {
        SULog(SULogLevelError, @"Searched %@ for %@.(app|pkg)", inUpdateFolder, bundleFileNameNoExtension);
    }
    return newAppDownloadPath;
}

+ (nullable id<SUInstallerProtocol>)installerForHost:(SUHost *)host fileOperationToolPath:(NSString *)fileOperationToolPath updateDirectory:(NSString *)updateDirectory error:(NSError * __autoreleasing *)error
{
    BOOL isPackage = NO;
    BOOL isGuided = NO;
    NSString *newDownloadPath = [self installSourcePathInUpdateFolder:updateDirectory forHost:host isPackage:&isPackage isGuided:&isGuided];
    
    if (newDownloadPath == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUMissingUpdateError userInfo:@{ NSLocalizedDescriptionKey: @"Couldn't find an appropriate update in the downloaded package." }];
        }
        return nil;
    }
    
    id <SUInstallerProtocol> installer;
    if (isPackage && isGuided) {
        installer = [[SUGuidedPackageInstaller alloc] initWithPackagePath:newDownloadPath installationPath:host.bundlePath fileOperationToolPath:fileOperationToolPath];
    } else if (isPackage) {
        installer = [[SUPackageInstaller alloc] initWithPackagePath:newDownloadPath installationPath:host.bundlePath];
    } else {
        NSString *normalizedInstallationPath = nil;
        if (SPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME) {
            normalizedInstallationPath = [self normalizedInstallationPathForHost:host];
        }
        
        // If we have a normalized path, we'll install to "#{CFBundleName}.app", but only if that path doesn't already exist. If we're "Foo 4.2.app," and there's a "Foo.app" in this directory, we don't want to overwrite it! But if there's no "Foo.app," we'll take that name.
        // Otherwise if there's no normalized path (the more likely case), we'll just use the host bundle's path
        NSString *installationPath;
        if (normalizedInstallationPath != nil && ![[NSFileManager defaultManager] fileExistsAtPath:normalizedInstallationPath]) {
            installationPath = normalizedInstallationPath;
        } else {
            installationPath = host.bundlePath;
        }
        
        installer = [[SUPlainInstaller alloc] initWithHost:host bundlePath:newDownloadPath installationPath:installationPath fileOperationToolPath:fileOperationToolPath];
    }
    return installer;
}

+ (NSString *)normalizedInstallationPathForHost:(SUHost *)host
{
    NSBundle *bundle = host.bundle;
    assert(bundle != nil);
    
    NSString *normalizedAppPath = [[[bundle bundlePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", [host objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleNameKey], [[bundle bundlePath] pathExtension]]];

    // Roundtrip string through fileSystemRepresentation to ensure it uses filesystem's Unicode normalization
    // rather than arbitrary Unicode form from Info.plist - #1017
    return [NSString stringWithUTF8String:[normalizedAppPath fileSystemRepresentation]];
}

@end
