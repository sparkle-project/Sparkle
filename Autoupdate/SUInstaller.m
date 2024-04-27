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
#import "SUGuidedPackageInstaller.h"
#import "SUHost.h"
#import "SUConstants.h"
#import "SULog.h"
#import "SUErrors.h"
#import "SPUInstallationType.h"
#import "SUNormalization.h"


#include "AppKitPrevention.h"

@implementation SUInstaller

+ (nullable NSString *)installSourcePathInUpdateFolder:(NSString *)inUpdateFolder forHost:(SUHost *)host
#if SPARKLE_BUILD_PACKAGE_SUPPORT
                                             isPackage:(BOOL *)isPackagePtr isGuided:(BOOL *)isGuidedPtr
#endif
{
    NSParameterAssert(inUpdateFolder);
    NSParameterAssert(host);

    // Search subdirectories for the application
    NSString *currentFile,
        *newAppDownloadPath = nil,
        *bundleFileName = [[host bundlePath] lastPathComponent],
        *alternateBundleFileName = [[host name] stringByAppendingPathExtension:[[host bundlePath] pathExtension]];
#if SPARKLE_BUILD_PACKAGE_SUPPORT
    NSString *fallbackPackagePath = nil;
    
    BOOL isPackage = NO;
    BOOL isGuided = YES;
#endif
    NSDirectoryEnumerator *dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:inUpdateFolder];
    NSString *bundleFileNameNoExtension = [bundleFileName stringByDeletingPathExtension];

    while ((currentFile = [dirEnum nextObject])) {
        NSString *currentPath = [inUpdateFolder stringByAppendingPathComponent:currentFile];
        
        // Ignore all symbolic links and aliases
        {
            NSURL *currentPathURL = [NSURL fileURLWithPath:currentPath];
            
            NSNumber *symbolicLinkFlag = nil;
            [currentPathURL getResourceValue:&symbolicLinkFlag forKey:NSURLIsSymbolicLinkKey error:NULL];
            if (symbolicLinkFlag.boolValue) {
                // NSDirectoryEnumerator won't recurse into symlinked directories
                continue;
            }
            
            NSNumber *aliasFlag = nil;
            [currentPathURL getResourceValue:&aliasFlag forKey:NSURLIsAliasFileKey error:NULL];
            
            if (aliasFlag.boolValue) {
                NSNumber *directoryFlag = nil;
                [currentPathURL getResourceValue:&directoryFlag forKey:NSURLIsDirectoryKey error:NULL];

                // Some DMGs have symlinks into /Applications! That's no good!
                if (directoryFlag.boolValue) {
                    [dirEnum skipDescendents];
                }
                
                continue;
            }
        }
        
        NSString *currentFilename = [currentFile lastPathComponent];
#if SPARKLE_BUILD_PACKAGE_SUPPORT
        NSString *currentExtension = [currentFile pathExtension];
        NSString *currentFilenameNoExtension = [currentFilename stringByDeletingPathExtension];
#endif
        if ([currentFilename isEqualToString:bundleFileName] ||
            [currentFilename isEqualToString:alternateBundleFileName]) // We found one!
        {
#if SPARKLE_BUILD_PACKAGE_SUPPORT
            isPackage = NO;
#endif
            newAppDownloadPath = currentPath;
            break;
#if SPARKLE_BUILD_PACKAGE_SUPPORT
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
#endif
        } else {
            // Try matching on bundle identifiers in case the user has changed the name of the host app
            NSBundle *incomingBundle = [NSBundle bundleWithPath:currentPath];
            NSString *hostBundleIdentifier = host.bundle.bundleIdentifier;
            if (incomingBundle && [incomingBundle.bundleIdentifier isEqualToString:hostBundleIdentifier]) {
#if SPARKLE_BUILD_PACKAGE_SUPPORT
                isPackage = NO;
#endif
                newAppDownloadPath = currentPath;
                break;
            }
        }
    }

#if SPARKLE_BUILD_PACKAGE_SUPPORT
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
    
#endif

    if (!newAppDownloadPath) {
        SULog(SULogLevelError, @"Searched %@ for %@.(app%@)", inUpdateFolder, bundleFileNameNoExtension,
#if SPARKLE_BUILD_PACKAGE_SUPPORT
              @"|pkg"
#else
              @""
#endif
              );
    }
    return newAppDownloadPath;
}

+ (nullable id<SUInstallerProtocol>)installerForHost:(SUHost *)host expectedInstallationType:(NSString *)expectedInstallationType updateDirectory:(NSString *)updateDirectory homeDirectory:(NSString *)homeDirectory userName:(NSString *)userName error:(NSError * __autoreleasing *)error
{
#if SPARKLE_BUILD_PACKAGE_SUPPORT
    BOOL isPackage = NO;
    BOOL isGuided = NO;
#endif
    
    NSString *newDownloadPath = [self installSourcePathInUpdateFolder:updateDirectory forHost:host
#if SPARKLE_BUILD_PACKAGE_SUPPORT
                                                            isPackage:&isPackage isGuided:&isGuided
#endif
    ];
    
    if (newDownloadPath == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUMissingUpdateError userInfo:@{ NSLocalizedDescriptionKey: @"Couldn't find an appropriate update in the downloaded package." }];
        }
        return nil;
    }
    
    // Make sure we find the type of installer that we were expecting to find
    // We shouldn't implicitly trust the installation type fed into here from the appcast because the installation type helps us determine
    // ahead of time whether or not this installer tool should be ran as root or not
    id <SUInstallerProtocol> installer = nil;
#if SPARKLE_BUILD_PACKAGE_SUPPORT
    if (isPackage && isGuided) {
        if (![expectedInstallationType isEqualToString:SPUInstallationTypeGuidedPackage]) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Found guided package installer but '%@=%@' was probably missing in the appcast item enclosure", SUAppcastAttributeInstallationType, SPUInstallationTypeGuidedPackage] }];
            }
        } else {
            installer = [[SUGuidedPackageInstaller alloc] initWithPackagePath:newDownloadPath homeDirectory:homeDirectory userName:userName];
        }
    } else if (isPackage) {
        if (![expectedInstallationType isEqualToString:SPUInstallationTypeInteractivePackage]) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Found package installer but '%@=%@' was probably missing in the appcast item enclosure", SUAppcastAttributeInstallationType, SPUInstallationTypeInteractivePackage] }];
            }
        } else {
            installer = [[SUPackageInstaller alloc] initWithPackagePath:newDownloadPath];
        }
    } else
#endif
    {
        if (![expectedInstallationType isEqualToString:SPUInstallationTypeApplication]) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Found regular application update but expected '%@=%@' from the appcast item enclosure instead", SUAppcastAttributeInstallationType, expectedInstallationType] }];
            }
        } else {
            NSString *normalizedInstallationPath = nil;
            if (SPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME) {
                normalizedInstallationPath = SUNormalizedInstallationPath(host);
            }
            
            // If we have a normalized path, we'll install to "#{CFBundleName}.app", but only if that path doesn't already exist. If we're "Foo 4.2.app," and there's a "Foo.app" in this directory, we don't want to overwrite it! But if there's no "Foo.app," we'll take that name.
            // Otherwise if there's no normalized path (the more likely case), we'll just use the host bundle's path
            // Check progress agent app which computes normalized path too according to these rules
            NSString *installationPath;
            if (normalizedInstallationPath != nil && ![[NSFileManager defaultManager] fileExistsAtPath:normalizedInstallationPath]) {
                installationPath = normalizedInstallationPath;
            } else {
                installationPath = host.bundlePath;
            }
            
            installer = [[SUPlainInstaller alloc] initWithHost:host bundlePath:newDownloadPath installationPath:installationPath];
        }
    }
    
    return installer;
}

@end
