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

@end

@implementation SUPlainInstaller

@synthesize host = _host;
@synthesize bundlePath = _bundlePath;
@synthesize installationPath = _installationPath;

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

- (BOOL)startInstallationToURL:(NSURL *)installationURL fromUpdateAtURL:(NSURL *)newURL withHost:(SUHost *)host error:(NSError * __autoreleasing *)error
{
    if (installationURL == nil || newURL == nil) {
        // this really shouldn't happen but just in case
        SULog(SULogLevelError, @"Failed to perform installation because either installation URL (%@) or new URL (%@) is nil", installationURL, newURL);
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: @"Failed to perform installation because the paths to install at and from are not valid" }];
        }
        return NO;
    }
    
    SUFileManager *fileManager = [[SUFileManager alloc] init];
    
    // Update the access time of our entire application before moving it into a temporary directory
    // The system periodically cleans up files by looking at the mod & access times, so we have to make sure they're up to date
    // They could be potentially be preserved when archiving an application, but also an update could just be sitting on the system for a long time
    // before being installed
    if (![fileManager updateAccessTimeOfItemAtRootURL:newURL error:error]) {
        SULog(SULogLevelError, @"Failed to recursively update new application's modification time before moving into temporary directory");
        return NO;
    }
    
    // Create a temporary directory for our new app that resides on our destination's volume
    NSString *preferredName = [installationURL.lastPathComponent.stringByDeletingPathExtension stringByAppendingString:@" (Incomplete Update)"];
    NSURL *installationDirectory = installationURL.URLByDeletingLastPathComponent;
    NSURL *tempNewDirectoryURL = [fileManager makeTemporaryDirectoryWithPreferredName:preferredName appropriateForDirectoryURL:installationDirectory error:error];
    
    if (tempNewDirectoryURL == nil) {
        SULog(SULogLevelError, @"Failed to make new temp directory");
        return NO;
    }
    
    // Move the new app to our temporary directory
    NSString *newURLLastPathComponent = newURL.lastPathComponent;
    NSURL *newTempURL = [tempNewDirectoryURL URLByAppendingPathComponent:newURLLastPathComponent];
    if (![fileManager moveItemAtURL:newURL toURL:newTempURL error:error]) {
        SULog(SULogLevelError, @"Failed to move the new app from %@ to its temp directory at %@", newURL.path, newTempURL.path);
        [fileManager removeItemAtURL:tempNewDirectoryURL error:NULL];
        return NO;
    }
    
    // Release our new app from quarantine
    NSError *quarantineError = nil;
    if (![fileManager releaseItemFromQuarantineAtRootURL:newTempURL error:&quarantineError]) {
        // Not big enough of a deal to fail the entire installation
        SULog(SULogLevelError, @"Failed to release quarantine at %@ with error %@", newTempURL.path, quarantineError);
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
    
    // We must leave moving the app to its destination as the final step in installing it, so that
    // it's not possible our new app can be left in an incomplete state at the final destination
    if (![fileManager changeOwnerAndGroupOfItemAtRootURL:newTempURL toMatchURL:oldURL error:error]) {
        // But this is big enough of a deal to fail
        SULog(SULogLevelError, @"Failed to change owner and group of new app at %@ to match old app at %@", newTempURL.path, oldURL.path);
        [fileManager removeItemAtURL:tempNewDirectoryURL error:NULL];
        return NO;
    }
    
    NSError *touchError = nil;
    if (![fileManager updateModificationAndAccessTimeOfItemAtURL:newTempURL error:&touchError]) {
        // Not a fatal error, but a pretty unfortunate one
        SULog(SULogLevelError, @"Failed to update modification and access time of new app at %@", newTempURL.path);
        SULog(SULogLevelError, @"Error: %@", touchError);
    }
    
    // Decide on a destination name we should use for the older app when we move it around the file system
    NSString *oldDestinationName = oldURL.lastPathComponent.stringByDeletingPathExtension;
    NSString *oldDestinationNameWithPathExtension = oldURL.lastPathComponent;
    
    // Create a temporary directory for our old app that resides on its volume
    NSURL *oldDirectoryURL = oldURL.URLByDeletingLastPathComponent;
    NSURL *tempOldDirectoryURL = (oldDirectoryURL != nil) ? [fileManager makeTemporaryDirectoryWithPreferredName:oldDestinationName appropriateForDirectoryURL:oldDirectoryURL error:error] : nil;
    if (tempOldDirectoryURL == nil) {
        SULog(SULogLevelError, @"Failed to create temporary directory for old app at %@", oldURL.path);
        [fileManager removeItemAtURL:tempNewDirectoryURL error:NULL];
        return NO;
    }
    
    // Move the old app to the temporary directory
    NSURL *oldTempURL = [tempOldDirectoryURL URLByAppendingPathComponent:oldDestinationNameWithPathExtension];
    if (![fileManager moveItemAtURL:oldURL toURL:oldTempURL error:error]) {
        SULog(SULogLevelError, @"Failed to move the old app at %@ to a temporary location at %@", oldURL.path, oldTempURL.path);
        
        // Just forget about our updated app on failure
        [fileManager removeItemAtURL:tempNewDirectoryURL error:NULL];
        [fileManager removeItemAtURL:tempOldDirectoryURL error:NULL];
        
        return NO;
    }
    
    // Move the new app to its final destination
    if (![fileManager moveItemAtURL:newTempURL toURL:installationURL error:error]) {
        SULog(SULogLevelError, @"Failed to move new app at %@ to final destination %@", newTempURL.path, installationURL.path);
        
        // Forget about our updated app on failure
        [fileManager removeItemAtURL:tempNewDirectoryURL error:NULL];
        
        // Attempt to restore our old app back the way it was on failure
        [fileManager moveItemAtURL:oldTempURL toURL:oldURL error:NULL];
        [fileManager removeItemAtURL:tempOldDirectoryURL error:NULL];
        
        return NO;
    }
    
    // Cleanup
    [fileManager removeItemAtURL:tempOldDirectoryURL error:NULL];
    [fileManager removeItemAtURL:tempNewDirectoryURL error:NULL];
    
    return YES;
}

- (BOOL)performInitialInstallation:(NSError * __autoreleasing *)error
{
    BOOL allowDowngrades = SPARKLE_AUTOMATED_DOWNGRADES;
    
    // Prevent malicious downgrades
    // Note that we may not be able to do this for package installations, hence this code being done here
    if (!allowDowngrades) {
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
    }
    
    return YES;
}

- (BOOL)performFinalInstallation:(NSError * __autoreleasing *)error
{
    // Note: we must do most installation work in the third stage due to relying on our application sitting in temporary directories.
    // It must not be possible for our update to sit in temporary directories for a very long time.
    return [self startInstallationToURL:[NSURL fileURLWithPath:self.installationPath] fromUpdateAtURL:[NSURL fileURLWithPath:self.bundlePath] withHost:self.host error:error];
}

- (BOOL)canInstallSilently
{
    return YES;
}

@end
