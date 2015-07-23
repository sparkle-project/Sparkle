//
//  SUPlainInstaller.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/10/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPlainInstaller.h"
#import "SUFileManager.h"
#import "SUCodeSigningVerifier.h"
#import "SUConstants.h"
#import "SUHost.h"
#import "SULog.h"

@implementation SUPlainInstaller

+ (BOOL)performInstallationToURL:(NSURL *)installationURL withOldURL:(NSURL *)oldURL newURL:(NSURL *)newURL error:(NSError * __autoreleasing *)error
{
    SUFileManager *fileManager = [[SUFileManager alloc] init];
    
    // Create a temporary directory for our new app that resides on our destination's volume
    NSURL *tempNewDirectoryURL = [fileManager makeTemporaryDirectoryWithPreferredName:[installationURL.lastPathComponent.stringByDeletingPathExtension stringByAppendingString:@" (Incomplete)"] appropriateForDirectoryURL:installationURL.URLByDeletingLastPathComponent error:error];
    if (tempNewDirectoryURL == nil) {
        SULog(@"Failed to make new temp directory");
        return NO;
    }
    
    // Move the new app to our temporary directory
    NSURL *newTempURL = [tempNewDirectoryURL URLByAppendingPathComponent:newURL.lastPathComponent];
    if (![fileManager moveItemAtURL:newURL toURL:newTempURL error:error]) {
        SULog(@"Failed to move the new app from %@ to its temp directory at %@", newURL.path, newTempURL.path);
        [fileManager removeItemAtURL:tempNewDirectoryURL error:NULL];
        return NO;
    }
    
    // Release our new app from quarantine and fix its owner and group IDs while it's at our temporary destination
    // We must leave moving the app to its destination as the final step in installing it, so that
    // it's not possible our new app can be left in an incomplete state at the final destination
    
    NSError *quarantineError = nil;
    if (![fileManager releaseItemFromQuarantineAtRootURL:newTempURL error:&quarantineError]) {
        // Not big enough of a deal to fail the entire installation
        SULog(@"Failed to release quarantine at %@ with error %@", newTempURL.path, quarantineError);
    }
    
    if (![fileManager changeOwnerAndGroupOfItemAtRootURL:newTempURL toMatchURL:oldURL error:error]) {
        // But this is big enough of a deal to fail
        SULog(@"Failed to change owner and group of new app at %@ to match old app at %@", newTempURL.path, oldURL.path);
        [fileManager removeItemAtURL:tempNewDirectoryURL error:NULL];
        return NO;
    }
    
    // If the installation and old URL differ, the sooner we can install our new app
    // because we won't have to move the old app out of the way first
    // increasing our chances of having it installed in case something goes wrong
    if (![installationURL isEqual:oldURL]) {
        // Move the new app to its final destination
        if (![fileManager moveItemAtURL:newTempURL toURL:installationURL error:error]) {
            SULog(@"Failed to move new app at %@ to final destination %@ (with installationURL != oldURL)", newTempURL.path, installationURL.path);
            [fileManager removeItemAtURL:tempNewDirectoryURL error:NULL];
            return NO;
        }
        
        // Cleanup: move the old app to the trash
        // We will first have to move the app to a temporary location that the user may not care about
        // This is necessary because the operation could fail mid-way through
        // Nothing past here will be a fatal error because we already installed the new app
        
        // Create a temporary directory for our old app that resides on its volume
        NSError *makeOldTempDirectoryError = nil;
        NSURL *tempOldDirectoryURL = [fileManager makeTemporaryDirectoryWithPreferredName:oldURL.lastPathComponent.stringByDeletingPathExtension appropriateForDirectoryURL:oldURL.URLByDeletingLastPathComponent error:&makeOldTempDirectoryError];
        if (tempOldDirectoryURL == nil) {
            SULog(@"Failed to create temporary directory for old app at %@ after finishing installation. This is not a fatal error. Error: %@", oldURL.path, makeOldTempDirectoryError);
        } else {
            // Move the old app to the temporary directory
            NSURL *oldTempURL = [tempOldDirectoryURL URLByAppendingPathComponent:oldURL.lastPathComponent];
            NSError *moveOldAppError = nil;
            if (![fileManager moveItemAtURL:oldURL toURL:oldTempURL error:&moveOldAppError]) {
                SULog(@"Failed to move the old app at %@ to a temporary location at %@. This is not a fatal error. Error: %@", oldURL.path, oldTempURL.path, moveOldAppError);
            } else {
                // Finally try to trash our old app
                NSError *trashError = nil;
                if (![fileManager moveItemAtURLToTrash:oldTempURL error:&trashError]) {
                    SULog(@"Failed to move %@ to trash. This is not a fatal error. Error: %@", oldURL, trashError);
                }
            }
            
            [fileManager removeItemAtURL:tempOldDirectoryURL error:NULL];
        }
    } else {
        // Create a temporary directory for our old app that resides on its volume
        NSURL *tempOldDirectoryURL = [fileManager makeTemporaryDirectoryWithPreferredName:oldURL.lastPathComponent.stringByDeletingPathExtension appropriateForDirectoryURL:oldURL.URLByDeletingLastPathComponent error:error];
        if (tempOldDirectoryURL == nil) {
            SULog(@"Failed to create temporary directory for old app at %@", oldURL.path);
            [fileManager removeItemAtURL:tempNewDirectoryURL error:NULL];
            return NO;
        }
        
        // Move the old app to the temporary directory
        NSURL *oldTempURL = [tempOldDirectoryURL URLByAppendingPathComponent:oldURL.lastPathComponent];
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
        
        // Cleanup: move the old app to the trash
        NSError *trashError = nil;
        if (![fileManager moveItemAtURLToTrash:oldTempURL error:&trashError]) {
            SULog(@"Failed to move %@ to trash with error %@", oldTempURL, trashError);
        }
        
        [fileManager removeItemAtURL:tempOldDirectoryURL error:NULL];
    }
    
    [fileManager removeItemAtURL:tempNewDirectoryURL error:NULL];
    
    return YES;
}

+ (void)performInstallationToPath:(NSString *)installationPath fromPath:(NSString *)path host:(SUHost *)host versionComparator:(id<SUVersionComparison>)comparator completionHandler:(void (^)(NSError *))completionHandler
{
    SUParameterAssert(host);

    // Prevent malicious downgrades
    if (![[[NSBundle bundleWithIdentifier:SUBundleIdentifier] infoDictionary][SUEnableAutomatedDowngradesKey] boolValue]) {
        if ([comparator compareVersion:[host version] toVersion:[[NSBundle bundleWithPath:path] objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey]] == NSOrderedDescending) {
            NSString *errorMessage = [NSString stringWithFormat:@"Sparkle Updater: Possible attack in progress! Attempting to \"upgrade\" from %@ to %@. Aborting update.", [host version], [[NSBundle bundleWithPath:path] objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey]];
            NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUDowngradeError userInfo:@{ NSLocalizedDescriptionKey: errorMessage }];
            [self finishInstallationToPath:installationPath withResult:NO error:error completionHandler:completionHandler];
            return;
        }
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSURL *oldURL = [NSURL fileURLWithPath:[host bundlePath]];
        NSURL *newURL = [NSURL fileURLWithPath:path];
        NSURL *installationURL = [NSURL fileURLWithPath:installationPath];
        
        BOOL result = [self performInstallationToURL:installationURL withOldURL:oldURL newURL:newURL error:&error];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishInstallationToPath:installationPath withResult:result error:error completionHandler:completionHandler];
        });
    });
}

@end
