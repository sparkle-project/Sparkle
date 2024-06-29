//
//  SUPlainInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPlainInstaller.h"
#import "SUFileManager.h"
#import "SUConstants.h"
#import "SUHost.h"
#import "SULog.h"
#import "SUErrors.h"
#import "SUVersionComparisonProtocol.h"
#import "SUStandardVersionComparator.h"
#import "SUCodeSigningVerifier.h"


#include "AppKitPrevention.h"

@implementation SUPlainInstaller
{
    SUHost *_host;
    NSString *_bundlePath;
    NSString *_installationPath;
    NSURL *_temporaryOldDirectory;
    // We get an obj-c warning if we use 'newTemporaryDirectory' name about new + ownership stuff, so use 'temporaryNewDirectory' instead
    NSURL *_temporaryNewDirectory;
    
    BOOL _newAndOldBundlesOnSameVolume;
    BOOL _canPerformSafeAtomicSwap;
}

- (instancetype)initWithHost:(SUHost *)host bundlePath:(NSString *)bundlePath installationPath:(NSString *)installationPath
{
    self = [super init];
    if (self != nil) {
        _host = host;
        _bundlePath = [bundlePath copy];
        _installationPath = [installationPath copy];
    }
    return self;
}

- (void)_performInitialInstallationWithFileManager:(SUFileManager *)fileManager oldBundleURL:(NSURL *)oldBundleURL newBundleURL:(NSURL *)newBundleURL performGatekeeperScan:(BOOL)performGatekeeperScan progressBlock:(nullable void(^)(double))progress SPU_OBJC_DIRECT
{
    // Release our new app from quarantine
    NSError *quarantineError = nil;
    if (![fileManager releaseItemFromQuarantineAtRootURL:newBundleURL error:&quarantineError]) {
        // Not big enough of a deal to fail the entire installation
        SULog(SULogLevelError, @"Failed to release quarantine at %@ with error %@", newBundleURL.path, quarantineError);
    }
    
    if (progress) {
        progress(5/11.0);
    }
    
    // Try to preserve Finder Tags
    NSArray *resourceTags = nil;
    BOOL retrievedResourceTags = [oldBundleURL getResourceValue:&resourceTags forKey:NSURLTagNamesKey error:NULL];
    if (retrievedResourceTags && resourceTags.count > 0) {
        [newBundleURL setResourceValue:resourceTags forKey:NSURLTagNamesKey error:NULL];
    }
    
    if (progress) {
        progress(6/11.0);
    }
    
    // Update owner and group (if possible)
    NSError *changeOwnerAndGroupError = nil;
    if (![fileManager changeOwnerAndGroupOfItemAtRootURL:newBundleURL toMatchURL:oldBundleURL error:&changeOwnerAndGroupError]) {
        // Not a fatal error
        SULog(SULogLevelError, @"Failed to change owner and group of new app at %@ to match old app at %@", newBundleURL.path, oldBundleURL.path);
        SULog(SULogLevelError, @"Error: %@", changeOwnerAndGroupError);
    }
    
    if (progress) {
        progress(7/11.0);
    }
    
    // Register the new bundle with LaunchServices and the system
    NSError *touchError = nil;
    if (![fileManager updateModificationAndAccessTimeOfItemAtURL:newBundleURL error:&touchError]) {
        // Not a fatal error, but a pretty unfortunate one
        SULog(SULogLevelError, @"Failed to update modification and access time of new app at %@", newBundleURL.path);
        SULog(SULogLevelError, @"Error: %@", touchError);
    }
    
    if (progress) {
        progress(8/11.0);
    }
    
    if (performGatekeeperScan) {
        // Perform a Gatekeeper scan to pre-warm the app launch
        // This avoids users seeing a "Verifying..." dialog when the installed update is launched
        // Note the tool we use to perform the Gatekeeper scan (gktool) is technically available on macOS 14.0,
        // however there are some potential bugs/issues with performing a Gatekeeper scan on versions before 14.4:
        // https://github.com/sparkle-project/Sparkle/issues/2491
        if (@available(macOS 14.4, *)) {
            // Only perform Gatekeeper scan if we're updating an app bundle
            NSString *newBundlePath = newBundleURL.path;
            if ([newBundlePath.pathExtension caseInsensitiveCompare:@"app"] == NSOrderedSame) {
                NSURL *gktoolURL = [NSURL fileURLWithPath:@"/usr/bin/gktool" isDirectory:NO];
                if ([gktoolURL checkResourceIsReachableAndReturnError:NULL]) {
                    NSTask *gatekeeperScanTask = [[NSTask alloc] init];
                    gatekeeperScanTask.executableURL = gktoolURL;
                    gatekeeperScanTask.arguments = @[@"scan", newBundlePath];

                    NSError *taskError;
                    if (![gatekeeperScanTask launchAndReturnError:&taskError]) {
                        // Not a fatal error
                        SULog(SULogLevelError, @"Failed to perform GateKeeper scan on '%@' with error %@", newBundlePath, taskError);
                    } else {
                        [gatekeeperScanTask waitUntilExit];
                        
                        if (gatekeeperScanTask.terminationStatus != 0) {
                            SULog(SULogLevelError, @"gktool failed and returned exit status %d", gatekeeperScanTask.terminationStatus);
                        }
                    }
                }
            }
        }
    }
}


- (BOOL)startInstallationToURL:(NSURL *)installationURL fromUpdateAtURL:(NSURL *)newURL withHost:(SUHost *)host progressBlock:(nullable void(^)(double))progress error:(NSError * __autoreleasing *)error SPU_OBJC_DIRECT
{
    if (installationURL == nil || newURL == nil) {
        // this really shouldn't happen but just in case
        SULog(SULogLevelError, @"Failed to perform installation because either installation URL (%@) or new URL (%@) is nil", installationURL, newURL);
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: @"Failed to perform installation because the paths to install at and from are not valid" }];
        }
        return NO;
    }

    if (progress) {
        progress(1/11.0);
    }

    SUFileManager *fileManager = [[SUFileManager alloc] init];

    // Update the access time of our entire application before moving it into a temporary directory
    // The system periodically cleans up files by looking at the mod & access times, so we have to make sure they're up to date
    // They could be potentially be preserved when archiving an application, but also an update could just be sitting on the system for a long time
    // before being installed
    if (!_newAndOldBundlesOnSameVolume) {
        NSError *accessTimeError = nil;
        if (![fileManager updateAccessTimeOfItemAtRootURL:newURL error:&accessTimeError]) {
            if (error != NULL) {
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{ NSLocalizedDescriptionKey: @"Failed to recursively update new application's modification time before moving into temporary directory" }];
                
                if (accessTimeError != nil) {
                    userInfo[NSUnderlyingErrorKey] = accessTimeError;
                }
                
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:userInfo];
            }
            
            return NO;
        }
    }
    
    NSURL *oldURL = [NSURL fileURLWithPath:host.bundlePath];
    if (oldURL == nil) {
        // this really shouldn't happen but just in case
        SULog(SULogLevelError, @"Failed to construct URL from bundle path: %@", host.bundlePath);
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: @"Failed to perform installation because a path could not be constructed for the old installation" }];
        }
        return NO;
    }
    
    if (progress) {
        progress(2/11.0);
    }
    
    NSURL *tempNewDirectoryURL;
    if (!_newAndOldBundlesOnSameVolume) {
        // Create a temporary directory for our new app that resides on our destination's volume
        // We use oldURL here instead of installationURL because in the case of normalization, installationURL may not exist
        // And we don't want to use either of the URL's parent directories because the parent directory could be on a different volume
        tempNewDirectoryURL = [fileManager makeTemporaryDirectoryAppropriateForDirectoryURL:oldURL error:error];
        if (tempNewDirectoryURL == nil) {
            return NO;
        }
        
        _temporaryNewDirectory = tempNewDirectoryURL;
    } else {
        tempNewDirectoryURL = nil;
    }

    if (progress) {
        progress(3/11.0);
    }

    // Move the new app to our temporary directory if needed
    NSURL *newFinalURL;
    if (!_newAndOldBundlesOnSameVolume) {
        NSString *newURLLastPathComponent = newURL.lastPathComponent;
        newFinalURL = [tempNewDirectoryURL URLByAppendingPathComponent:newURLLastPathComponent];
        NSError *newTempMoveError = nil;
        if (![fileManager moveItemAtURL:newURL toURL:newFinalURL error:&newTempMoveError]) {
            if (error != NULL) {
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to move the new app from %@ to its temp directory at %@", newURL.path, newFinalURL.path] }];
                
                if (newTempMoveError != nil) {
                    userInfo[NSUnderlyingErrorKey] = newTempMoveError;
                }
                
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:userInfo];
            }
            return NO;
        }
    } else {
        newFinalURL = newURL;
    }

    if (progress) {
        progress(4/11.0);
    }
    
    if (!_newAndOldBundlesOnSameVolume) {
        // If we're updating a bundle on another volume, the install process can be pretty slow.
        // In this case let's get out of the way and skip the Gatekeeper scan
        [self _performInitialInstallationWithFileManager:fileManager oldBundleURL:oldURL newBundleURL:newFinalURL performGatekeeperScan:NO progressBlock:progress];
    }

    if (progress) {
        progress(9/11.0);
    }
    
    // First try swapping the application atomically
    NSError *swapError = nil;
    BOOL swappedApp;
    // If we can not safely perform an atomic swap, or if the app is normalized and the installation path differs, go through the old swap path
    if (!_canPerformSafeAtomicSwap || (SPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME && ![oldURL.path isEqual:installationURL.path])) {
        swappedApp = NO;
    } else {
        // We will be cleaning up the temporary directory later in -performCleanup:
        // We don't want to clean it up now because it can take some time
        swappedApp = [fileManager swapItemAtURL:installationURL withItemAtURL:newFinalURL error:&swapError];
    }
    
    if (!swappedApp) {
        // Otherwise swap out the old and new applications using the legacy path
        
        if (swapError != nil) {
            SULog(SULogLevelDefault, @"Invoking fallback from failing to replace original item with error: %@", swapError);
        }

        // Create a temporary directory for our old app that resides on its volume
        NSURL *tempOldDirectoryURL = [fileManager makeTemporaryDirectoryAppropriateForDirectoryURL:oldURL error:error];
        if (tempOldDirectoryURL == nil) {
            return NO;
        }
        
        _temporaryOldDirectory = tempOldDirectoryURL;

        if (progress) {
            progress(10/11.0);
        }
        
        NSString *oldURLFilename = oldURL.lastPathComponent;
        if (oldURLFilename == nil) {
            // this really shouldn't happen..
            SULog(SULogLevelError, @"Failed to retrieve last path component from old URL: %@", oldURL.path);
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: @"Failed to perform installation because the last path component of the old installation URL could not be constructed." }];
            }
            return NO;
        }
        
        // Move the old app to the temporary directory
        NSURL *oldTempURL = [tempOldDirectoryURL URLByAppendingPathComponent:oldURLFilename];
        NSError *oldMoveError = nil;
        if (![fileManager moveItemAtURL:oldURL toURL:oldTempURL error:&oldMoveError]) {
            if (error != NULL) {
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to move the old app at %@ to a temporary location at %@", oldURL.path, oldTempURL.path] }];
                
                if (oldMoveError != nil) {
                    userInfo[NSUnderlyingErrorKey] = oldMoveError;
                }
                
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:userInfo];
            }
            return NO;
        }

        if (progress) {
            progress(10.5/11.0);
        }

        // Move the new app to its final destination
        NSError *installMoveError = nil;
        if (![fileManager moveItemAtURL:newFinalURL toURL:installationURL error:&installMoveError]) {
            if (error != NULL) {
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to move new app at %@ to final destination %@", newFinalURL.path, installationURL.path] }];
                
                if (installMoveError != nil) {
                    userInfo[NSUnderlyingErrorKey] = installMoveError;
                }
                
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:userInfo];
            }
            
            // Attempt to restore our old app back the way it was on failure
            [fileManager moveItemAtURL:oldTempURL toURL:oldURL error:NULL];
            
            return NO;
        }
    }

    if (progress) {
        progress(11/11.0);
    }

    return YES;
}

- (BOOL)performInitialInstallation:(NSError * __autoreleasing *)error
{
    // Prevent malicious downgrades
    // Note that we may not be able to do this for package installations, hence this code being done here
    NSString *hostVersion = [_host version];
    
    NSBundle *bundle = [NSBundle bundleWithPath:_bundlePath];
    SUHost *updateHost = [[SUHost alloc] initWithBundle:bundle];
    NSString *updateVersion = [updateHost objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey];
    
    id<SUVersionComparison> comparator = [[SUStandardVersionComparator alloc] init];
    if (!updateVersion || [comparator compareVersion:hostVersion toVersion:updateVersion] == NSOrderedDescending) {
        
        if (error != NULL) {
            NSString *errorMessage = [NSString stringWithFormat:@"For security reasons, updates that downgrade version of the application are not allowed. Refusing to downgrade app from version %@ to %@. Aborting update.", hostVersion, updateVersion];
            
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUDowngradeError userInfo:@{ NSLocalizedDescriptionKey: errorMessage }];
        }
        
        return NO;
    }
    
    SUFileManager *fileManager = [[SUFileManager alloc] init];
    
    BOOL updateHasCustomUpdateSecurityPolicy = NO;
    if (@available(macOS 13.0, *)) {
        // If the new update is notarized / developer ID code signed and Autoupdate is not signed with the same Team ID as the new update,
        // then we may run into Privacy & Security prompt issues from the OS
        // which think we are modifying the update (but we're not)
        // To avoid these, we skip the gatekeeper scan and skip performing an atomic swap during install
        // If the update has a custom update security policy, the same team ID policy may not apply,
        // so in that case we will also skip performing an atomic swap
        
        NSURL *mainExecutableURL = NSBundle.mainBundle.executableURL;
        if (mainExecutableURL == nil) {
            // This shouldn't happen
            _canPerformSafeAtomicSwap = NO;
        } else {
            updateHasCustomUpdateSecurityPolicy = updateHost.hasUpdateSecurityPolicy;
            if (updateHasCustomUpdateSecurityPolicy) {
                // We don't handle working around a custom update security policy
                _canPerformSafeAtomicSwap = NO;
            } else {
                NSString *installerTeamIdentifier = [SUCodeSigningVerifier teamIdentifierAtURL:mainExecutableURL];
                NSString *bundleTeamIdentifier = [SUCodeSigningVerifier teamIdentifierAtURL:bundle.bundleURL];
                
                // If bundleTeamIdentifier is nil, then the update isn't code signed so atomic swap is okay
                _canPerformSafeAtomicSwap = (bundleTeamIdentifier == nil || (installerTeamIdentifier != nil && [installerTeamIdentifier isEqualToString:bundleTeamIdentifier]));
            }
        }
    } else {
        _canPerformSafeAtomicSwap = YES;
    }
    
    if (!_canPerformSafeAtomicSwap) {
        if (updateHasCustomUpdateSecurityPolicy) {
            SULog(SULogLevelDefault, @"Skipping atomic rename/swap and gatekeeper scan because new update %@ has a custom NSUpdateSecurityPolicy", bundle.bundleURL.lastPathComponent);
        } else {
            SULog(SULogLevelDefault, @"Skipping atomic rename/swap and gatekeeper scan because Autoupdate is not signed with same identity as the new update %@", bundle.bundleURL.lastPathComponent);
        }
    }
    
    _newAndOldBundlesOnSameVolume = [fileManager itemAtURL:bundle.bundleURL isOnSameVolumeItemAsURL:_host.bundle.bundleURL];
    
    // We can do a lot of the installation work ahead of time if the new app update does not need to be copied to another volume
    if (_newAndOldBundlesOnSameVolume) {
        [self _performInitialInstallationWithFileManager:fileManager oldBundleURL:_host.bundle.bundleURL newBundleURL:bundle.bundleURL performGatekeeperScan:_canPerformSafeAtomicSwap progressBlock:NULL];
    }
    
    return YES;
}

- (BOOL)performFinalInstallationProgressBlock:(nullable void(^)(double))cb error:(NSError *__autoreleasing*)error
{
    // Note: we must do most installation work in the third stage due to relying on our application sitting in temporary directories.
    // It must not be possible for our update to sit in temporary directories for a very long time.
    return [self startInstallationToURL:[NSURL fileURLWithPath:_installationPath] fromUpdateAtURL:[NSURL fileURLWithPath:_bundlePath] withHost:_host progressBlock:cb error:error];
}

- (void)performCleanup
{
    SUFileManager *fileManager = [[SUFileManager alloc] init];
    
    if (_temporaryNewDirectory != nil) {
        [fileManager removeItemAtURL:_temporaryNewDirectory error:NULL];
    }
    
    if (_temporaryOldDirectory != nil) {
        [fileManager removeItemAtURL:_temporaryOldDirectory error:NULL];
    }
}

- (BOOL)canInstallSilently
{
    return YES;
}

@end
