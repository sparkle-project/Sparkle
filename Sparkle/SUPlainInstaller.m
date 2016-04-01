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
#import "SUParameterAssert.h"
#import "SUVersionComparisonProtocol.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUPlainInstaller ()

@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, readonly) id <SUVersionComparison> comparator;
@property (nonatomic, copy, readonly) NSString *applicationPath;
@property (nonatomic, copy, readonly) NSString *installationPath;

// Properties that carry over from starting installation to resuming to cleaning up
@property (nonatomic) SUFileManager *fileManager;
@property (nonatomic) NSURL *tempOldDirectoryURL;
@property (nonatomic) NSURL *tempNewDirectoryURL;
@property (nonatomic) NSURL *oldTempURL;

@end

@implementation SUPlainInstaller

@synthesize host = _host;
@synthesize comparator = _comparator;
@synthesize applicationPath = _applicationPath;
@synthesize installationPath = _installationPath;
@synthesize fileManager = _fileManager;
@synthesize tempOldDirectoryURL = _tempOldDirectoryURL;
@synthesize tempNewDirectoryURL = _tempNewDirectoryURL;
@synthesize oldTempURL = _oldTempURL;

- (instancetype)initWithHost:(SUHost *)host applicationPath:(NSString *)applicationPath installationPath:(NSString *)installationPath versionComparator:(id <SUVersionComparison>)comparator
{
    self = [super init];
    if (self != nil) {
        _host = host;
        _applicationPath = [applicationPath copy];
        _installationPath = [installationPath copy];
        _comparator = comparator;
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
        SULog(@"Failed to perform installation because either installation URL (%@) or new URL (%@) is nil", installationURL, newURL);
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: @"Failed to perform installation because the paths to install at and from are not valid" }];
        }
        return NO;
    }
    
    SUFileManager *fileManager = self.fileManager;
    
    // Update the access and mod time of our entire application before moving it into a temporary directory
    // The system periodically cleans up files by looking at the mod & access times, so we have to make sure they're up to date
    // (they could be potentially be preserved when archiving an application...)
    if (![fileManager updateModificationAndAccessTimeOfItemsRecursivelyAtURL:newURL error:error]) {
        SULog(@"Failed to recursively update new application's modification time before moving into temporary directory");
        return NO;
    }
    
    // Create a temporary directory for our new app that resides on our destination's volume
    NSURL *tempNewDirectoryURL = [fileManager makeTemporaryDirectoryWithPreferredName:[installationURL.lastPathComponent.stringByDeletingPathExtension stringByAppendingString:@" (Incomplete Update)"] appropriateForDirectoryURL:installationURL.URLByDeletingLastPathComponent error:error];
    if (tempNewDirectoryURL == nil) {
        SULog(@"Failed to make new temp directory");
        return NO;
    }
    
    // Move the new app to our temporary directory
    NSString *newURLLastPathComponent = newURL.lastPathComponent;
    NSURL *newTempURL = [tempNewDirectoryURL URLByAppendingPathComponent:newURLLastPathComponent];
    if (![fileManager moveItemAtURL:newURL toURL:newTempURL error:error]) {
        SULog(@"Failed to move the new app from %@ to its temp directory at %@", newURL.path, newTempURL.path);
        [fileManager removeItemAtURL:tempNewDirectoryURL error:NULL];
        return NO;
    }
    
    // Release our new app from quarantine
    NSError *quarantineError = nil;
    if (![fileManager releaseItemFromQuarantineAtRootURL:newTempURL error:&quarantineError]) {
        // Not big enough of a deal to fail the entire installation
        SULog(@"Failed to release quarantine at %@ with error %@", newTempURL.path, quarantineError);
    }
    
    NSURL *oldURL = [NSURL fileURLWithPath:host.bundlePath];
    if (oldURL == nil) {
        // this really shouldn't happen but just in case
        SULog(@"Failed to construct URL from bundle path: %@", host.bundlePath);
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey: @"Failed to perform installation because a path could not be constructed for the old installation" }];
        }
        return NO;
    }
    
    // This is the first operation that has a high chance or prompting for auth. if the user needs to auth. at all
    // We must leave moving the app to its destination as the final step in installing it, so that
    // it's not possible our new app can be left in an incomplete state at the final destination
    if (![fileManager changeOwnerAndGroupOfItemAtRootURL:newTempURL toMatchURL:oldURL error:error]) {
        // But this is big enough of a deal to fail
        SULog(@"Failed to change owner and group of new app at %@ to match old app at %@", newTempURL.path, oldURL.path);
        [fileManager removeItemAtURL:tempNewDirectoryURL error:NULL];
        return NO;
    }
    
    NSError *touchError = nil;
    if (![fileManager updateModificationAndAccessTimeOfItemAtURL:newTempURL error:&touchError]) {
        // Not a fatal error, but a pretty unfortunate one
        SULog(@"Failed to update modification and access time of new app at %@", newTempURL.path);
        SULog(@"Error: %@", touchError);
    }
    
    // Decide on a destination name we should use for the older app when we move it around the file system
    NSString *oldDestinationName = nil;
    if (SPARKLE_APPEND_VERSION_NUMBER) {
        NSString *oldBundleVersion = [self bundleVersionAppropriateForFilenameFromHost:host];
        
        oldDestinationName = [oldURL.lastPathComponent.stringByDeletingPathExtension stringByAppendingFormat:@" (%@)", oldBundleVersion != nil ? oldBundleVersion : @"old"];
    } else {
        oldDestinationName = oldURL.lastPathComponent.stringByDeletingPathExtension;
    }
    
    NSString *oldURLExtension = oldURL.pathExtension;
    NSString *oldDestinationNameWithPathExtension = [oldDestinationName stringByAppendingPathExtension:oldURLExtension];
    
    // Create a temporary directory for our old app that resides on its volume
    NSURL *tempOldDirectoryURL = [fileManager makeTemporaryDirectoryWithPreferredName:oldDestinationName appropriateForDirectoryURL:oldURL.URLByDeletingLastPathComponent error:error];
    if (tempOldDirectoryURL == nil) {
        SULog(@"Failed to create temporary directory for old app at %@", oldURL.path);
        [fileManager removeItemAtURL:tempNewDirectoryURL error:NULL];
        return NO;
    }
    
    // Move the old app to the temporary directory
    NSURL *oldTempURL = [tempOldDirectoryURL URLByAppendingPathComponent:oldDestinationNameWithPathExtension];
    if (![fileManager moveItemAtURL:oldURL toURL:oldTempURL error:error]) {
        SULog(@"Failed to move the old app at %@ to a temporary location at %@", oldURL.path, oldTempURL.path);
        
        // Just forget about our updated app on failure
        [fileManager removeItemAtURL:tempNewDirectoryURL error:NULL];
        [fileManager removeItemAtURL:tempOldDirectoryURL error:NULL];
        
        return NO;
    }
    
    // Move the new app to its final destination
    if (![fileManager moveItemAtURL:newTempURL toURL:installationURL error:error]) {
        SULog(@"Failed to move new app at %@ to final destination %@", newTempURL.path, installationURL.path);
        
        // Forget about our updated app on failure
        [fileManager removeItemAtURL:tempNewDirectoryURL error:NULL];
        
        // Attempt to restore our old app back the way it was on failure
        [fileManager moveItemAtURL:oldTempURL toURL:oldURL error:NULL];
        [fileManager removeItemAtURL:tempOldDirectoryURL error:NULL];
        
        return NO;
    }
    
    // To carry over when we clean up the installation
    self.fileManager = fileManager;
    self.tempNewDirectoryURL = tempNewDirectoryURL;
    self.tempOldDirectoryURL = tempOldDirectoryURL;
    self.oldTempURL = oldTempURL;
    
    return YES;
}

- (BOOL)performFirstStage:(NSError * __autoreleasing *)error
{
    BOOL allowDowngrades = SPARKLE_AUTOMATED_DOWNGRADES;
    
    // Prevent malicious downgrades
    // Note that we may not be able to do this for package installations, hence this code being done here
    if (!allowDowngrades) {
        NSBundle *bundle = [NSBundle bundleWithPath:self.applicationPath];
        
        if ([self.comparator compareVersion:self.host.version toVersion:[bundle objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey]] == NSOrderedDescending) {
            if (error != NULL) {
                NSString *errorMessage = [NSString stringWithFormat:@"Sparkle Updater: Possible attack in progress! Attempting to \"upgrade\" from %@ to %@. Aborting update.", self.host.version, [bundle objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey]];
                
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUDowngradeError userInfo:@{ NSLocalizedDescriptionKey: errorMessage }];
            }
            
            return NO;
        }
    }
    
    return YES;
}

- (BOOL)performSecondStageAllowingUI:(BOOL)allowsUI error:(NSError *__autoreleasing *)error
{
    self.fileManager = [SUFileManager fileManagerAllowingAuthorization:allowsUI];
    
    // Temporary hack for bringing authorization prompt right away if we need it
    // Ideally, bringing up the authorization prompt may be done before extraction occurs
    return [self.fileManager updateModificationAndAccessTimeOfItemAtURL:self.host.bundle.bundleURL error:error];
}

- (BOOL)performThirdStage:(NSError * __autoreleasing *)error
{
    // Note: we must do most installation work in the third stage due to relying on our application sitting in temporary directories.
    // It must not be possible for our update to sit in temporary directories for a very long time.
    return [self startInstallationToURL:[NSURL fileURLWithPath:self.installationPath] fromUpdateAtURL:[NSURL fileURLWithPath:self.applicationPath] withHost:self.host error:error];
}

- (void)cleanup
{
    SUFileManager *fileManager = self.fileManager;
    NSURL *oldTempURL = self.oldTempURL;
    NSURL *tempOldDirectoryURL = self.tempOldDirectoryURL;
    NSURL *tempNewDirectoryURL = self.tempNewDirectoryURL;
    
    // Note: I'm intentionally not checking if an item at the file URLs exist since these methods already do that for us
    
    if (oldTempURL != nil) {
        // Cleanup: move the old app to the trash
        NSError *trashError = nil;
        if (![fileManager moveItemAtURLToTrash:oldTempURL error:&trashError]) {
            SULog(@"Failed to move %@ to trash with error %@", oldTempURL, trashError);
        }
        
        self.oldTempURL = nil;
    }
    
    if (tempOldDirectoryURL != nil) {
        [fileManager removeItemAtURL:tempOldDirectoryURL error:NULL];
        
        self.tempOldDirectoryURL = nil;
    }
    
    if (tempNewDirectoryURL != nil) {
        [fileManager removeItemAtURL:tempNewDirectoryURL error:NULL];
        
        self.tempNewDirectoryURL = nil;
    }
}

@end
