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


#include "AppKitPrevention.h"

@interface SUPlainInstaller ()

@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, copy, readonly) NSString *bundlePath;
@property (nonatomic, copy, readonly) NSString *installationPath;

@property (nonatomic) NSURL *temporaryOldDirectory;
// We get an obj-c warning if we use 'newTemporaryDirectory' name about new + ownership stuff, so use 'temporaryNewDirectory' instead
@property (nonatomic) NSURL *temporaryNewDirectory;

@end

@implementation SUPlainInstaller

@synthesize host = _host;
@synthesize bundlePath = _bundlePath;
@synthesize installationPath = _installationPath;
@synthesize temporaryOldDirectory = _temporaryOldDirectory;
@synthesize temporaryNewDirectory = _temporaryNewDirectory;

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

// Returns the bundle version from the specified host that is appropriate to use as a filename, or nil if we're unable to retrieve one
- (NSString *)bundleVersionAppropriateForFilenameFromHost:(SUHost *)host
{
    NSString *bundleVersion = [host objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey];
    NSString *trimmedVersion = @"";
    
    if (bundleVersion != nil) {
        NSMutableCharacterSet *validCharacters = [NSMutableCharacterSet alphanumericCharacterSet];
        [validCharacters formUnionWithCharacterSet:[NSCharacterSet characterSetWithCharactersInString:@".-()"]];
        
        trimmedVersion = [bundleVersion stringByTrimmingCharactersInSet:[validCharacters invertedSet]];
    }
    
    return trimmedVersion.length > 0 ? trimmedVersion : nil;
}

- (BOOL)startInstallationToURL:(NSURL *)installationURL fromUpdateAtURL:(NSURL *)newURL withHost:(SUHost *)host progressBlock:(nullable void(^)(double))progress  error:(NSError * __autoreleasing *)error
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
        progress(1/10.0);
    }

    SUFileManager *fileManager = [[SUFileManager alloc] init];

    // Update the access time of our entire application before moving it into a temporary directory
    // The system periodically cleans up files by looking at the mod & access times, so we have to make sure they're up to date
    // They could be potentially be preserved when archiving an application, but also an update could just be sitting on the system for a long time
    // before being installed
    if (![fileManager updateAccessTimeOfItemAtRootURL:newURL error:error]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: @"Failed to recursively update new application's modification time before moving into temporary directory" }];
        }
        
        return NO;
    }
    
    // Create a temporary directory for our new app that resides on our destination's volume
    NSString *preferredName = [installationURL.lastPathComponent.stringByDeletingPathExtension stringByAppendingString:@" (Incomplete Update)"];
    NSURL *installationDirectory = installationURL.URLByDeletingLastPathComponent;
    NSURL *tempNewDirectoryURL = [fileManager makeTemporaryDirectoryWithPreferredName:preferredName appropriateForDirectoryURL:installationDirectory error:error];
    
    if (tempNewDirectoryURL == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: @"Failed to make new temporary directory" }];
        }
        
        return NO;
    }
    
    self.temporaryNewDirectory = tempNewDirectoryURL;

    if (progress) {
        progress(2/10.0);
    }

    // Move the new app to our temporary directory
    NSString *newURLLastPathComponent = newURL.lastPathComponent;
    NSURL *newTempURL = [tempNewDirectoryURL URLByAppendingPathComponent:newURLLastPathComponent];
    if (![fileManager moveItemAtURL:newURL toURL:newTempURL error:error]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to move the new app from %@ to its temp directory at %@", newURL.path, newTempURL.path] }];
        }
        return NO;
    }

    if (progress) {
        progress(3/10.0);
    }

    // Release our new app from quarantine
    NSError *quarantineError = nil;
    if (![fileManager releaseItemFromQuarantineAtRootURL:newTempURL error:&quarantineError]) {
        // Not big enough of a deal to fail the entire installation
        SULog(SULogLevelError, @"Failed to release quarantine at %@ with error %@", newTempURL.path, quarantineError);
    }

    if (progress) {
        progress(4/10.0);
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
    
    // Try to preserve Finder Tags
    NSArray *resourceTags = nil;
    BOOL retrievedResourceTags = [oldURL getResourceValue:&resourceTags forKey:NSURLTagNamesKey error:NULL];
    if (retrievedResourceTags && resourceTags.count > 0) {
        [newTempURL setResourceValue:resourceTags forKey:NSURLTagNamesKey error:NULL];
    }
    
    // We must leave moving the app to its destination as the final step in installing it, so that
    // it's not possible our new app can be left in an incomplete state at the final destination
    
    NSError *changeOwnerAndGroupError = nil;
    if (![fileManager changeOwnerAndGroupOfItemAtRootURL:newTempURL toMatchURL:oldURL error:&changeOwnerAndGroupError]) {
        // Not a fatal error
        SULog(SULogLevelError, @"Failed to change owner and group of new app at %@ to match old app at %@", newTempURL.path, oldURL.path);
        SULog(SULogLevelError, @"Error: %@", changeOwnerAndGroupError);
    }

    if (progress) {
        progress(5/10.0);
    }

    NSError *touchError = nil;
    if (![fileManager updateModificationAndAccessTimeOfItemAtURL:newTempURL error:&touchError]) {
        // Not a fatal error, but a pretty unfortunate one
        SULog(SULogLevelError, @"Failed to update modification and access time of new app at %@", newTempURL.path);
        SULog(SULogLevelError, @"Error: %@", touchError);
    }

    if (progress) {
        progress(6/10.0);
    }
    
    // First try replacing the application atomically
    NSError *replaceError = nil;
    BOOL replacedApp;
    if (@available(macOS 10.13, *)) {
        // If the app is normalized and the installation path differs, go through the old swap path
        if (SPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME && ![oldURL.path isEqual:installationURL.path]) {
            replacedApp = NO;
        } else {
            // Note: in my experience, a clone of the app may still be left at newTempURL
            // This is OK though because we will be cleaning up the temporary directory later in -performCleanup:
            replacedApp = [fileManager replaceItemAtURL:installationURL withItemAtURL:newTempURL error:&replaceError];
        }
    } else {
        replacedApp = NO;
    }
    
    if (!replacedApp) {
        // Otherwise swap out the old and new applications using the legacy path
        
        if (replaceError != nil) {
            SULog(SULogLevelDefault, @"Invoking fallback from failing to replace original item with error: %@", replaceError);
        }
        
        // Decide on a destination name we should use for the older app when we move it around the file system
        NSString *oldDestinationName = oldURL.lastPathComponent.stringByDeletingPathExtension;
        NSString *oldDestinationNameWithPathExtension = oldURL.lastPathComponent;

        // Create a temporary directory for our old app that resides on its volume
        NSURL *oldDirectoryURL = oldURL.URLByDeletingLastPathComponent;
        NSURL *tempOldDirectoryURL = (oldDirectoryURL != nil) ? [fileManager makeTemporaryDirectoryWithPreferredName:oldDestinationName appropriateForDirectoryURL:oldDirectoryURL error:error] : nil;
        if (tempOldDirectoryURL == nil) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to create temporary directory for old app at %@", oldURL.path] }];
            }
            return NO;
        }
        
        self.temporaryOldDirectory = tempOldDirectoryURL;

        if (progress) {
            progress(7/10.0);
        }
        
        // Move the old app to the temporary directory
        NSURL *oldTempURL = [tempOldDirectoryURL URLByAppendingPathComponent:oldDestinationNameWithPathExtension];
        if (![fileManager moveItemAtURL:oldURL toURL:oldTempURL error:error]) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to move the old app at %@ to a temporary location at %@", oldURL.path, oldTempURL.path] }];
            }
            return NO;
        }

        if (progress) {
            progress(8/10.0);
        }

        // Move the new app to its final destination
        if (![fileManager moveItemAtURL:newTempURL toURL:installationURL error:error]) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to move new app at %@ to final destination %@", newTempURL.path, installationURL.path] }];
            }
            
            // Attempt to restore our old app back the way it was on failure
            [fileManager moveItemAtURL:oldTempURL toURL:oldURL error:NULL];
            
            return NO;
        }
        
        if (progress) {
            progress(9/10.0);
        }
    }

    if (progress) {
        progress(10/10.0);
    }

    return YES;
}

- (BOOL)performInitialInstallation:(NSError * __autoreleasing *)error
{
    // Prevent malicious downgrades
    // Note that we may not be able to do this for package installations, hence this code being done here
    NSString *hostVersion = [self.host version];
    
    NSBundle *bundle = [NSBundle bundleWithPath:self.bundlePath];
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
    
    return YES;
}

- (BOOL)performFinalInstallationProgressBlock:(nullable void(^)(double))cb error:(NSError *__autoreleasing*)error
{
    // Note: we must do most installation work in the third stage due to relying on our application sitting in temporary directories.
    // It must not be possible for our update to sit in temporary directories for a very long time.
    return [self startInstallationToURL:[NSURL fileURLWithPath:self.installationPath] fromUpdateAtURL:[NSURL fileURLWithPath:self.bundlePath] withHost:self.host progressBlock:cb error:error];
}

- (void)performCleanup
{
    SUFileManager *fileManager = [[SUFileManager alloc] init];
    
    if (self.temporaryNewDirectory != nil) {
        [fileManager removeItemAtURL:self.temporaryNewDirectory error:NULL];
    }
    
    if (self.temporaryOldDirectory != nil) {
        [fileManager removeItemAtURL:self.temporaryOldDirectory error:NULL];
    }
}

- (BOOL)canInstallSilently
{
    return YES;
}

@end
