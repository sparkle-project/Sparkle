//
//  SULocalCacheDirectory.m
//  Sparkle
//
//  Created by Mayur Pawashe on 6/23/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPULocalCacheDirectory.h"
#import "SULog.h"


#include "AppKitPrevention.h"

static NSTimeInterval OLD_ITEM_DELETION_INTERVAL = 86400 * 10; // 10 days

@implementation SPULocalCacheDirectory

+ (NSString *)_cachePathForCacheDirectory:(NSURL *)cacheURL bundleIdentifier:(NSString *)bundleIdentifier SPU_OBJC_DIRECT
{
    NSString *appCacheIdentifier = bundleIdentifier;
    {
        // If an app has an ill-formed bundle identifier that ends with ".app" or ".service"
        // or anything similarly problematic, we will append ".sparkle" to it
        // so that the cache directory doesn't look like a protected bundle directory,
        // which can cause other systematic issues
        // https://github.com/sparkle-project/Sparkle/discussions/2881
        NSArray<NSString *> *problematicBundleIdentifierExtensions = @[@".app", @".service", @".xpc", @".appex", @".bundle", @".plugin", @".saver", @".kext"];
        
        // Transforming the bundle identifier into a lowercased variant for suffix comparison
        // rather than case-insensitive comparing the pathExtension (which may return "" for ".app")
        NSString *lowercasedBundleIdentifier = bundleIdentifier.lowercaseString;
        for (NSString *badExtension in problematicBundleIdentifierExtensions) {
            if ([lowercasedBundleIdentifier hasSuffix:badExtension]) {
                appCacheIdentifier = [bundleIdentifier stringByAppendingString:@".sparkle"];
                break;
            }
        }
    }
    
    NSString *resultPath = [[[cacheURL URLByAppendingPathComponent:appCacheIdentifier isDirectory:YES] URLByAppendingPathComponent:@SPARKLE_BUNDLE_IDENTIFIER isDirectory:YES] path];
    assert(resultPath != nil);
    
    return resultPath;
}

// It is important to note this may return a different path whether invoked from a sanboxed vs non-sandboxed process
// For this reason, this method should not be a part of SUHost because its behavior depends on what kind of process it's being invoked from
+ (NSString *)cachePathForBundleIdentifier:(NSString *)bundleIdentifier
{
    NSURL *cacheURL = [[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:NULL];
    assert(cacheURL != nil);
    
    return [self _cachePathForCacheDirectory:cacheURL bundleIdentifier:bundleIdentifier];
}

+ (void)removeOldItemsInDirectory:(NSString *)directory
{
    NSMutableArray<NSString *> *filePathsToRemove = [NSMutableArray array];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    NSDirectoryEnumerator *directoryEnumerator = [fileManager enumeratorAtPath:directory];
    NSDate *currentDate = [NSDate date];
    for (NSString *filename in directoryEnumerator) {
        NSString *filePath = [directory stringByAppendingPathComponent:filename];
        NSDictionary<NSString *, id> *fileAttributes = [fileManager attributesOfItemAtPath:filePath error:NULL];
        if (fileAttributes != nil) {
            NSDate *lastModificationDate = [fileAttributes objectForKey:NSFileModificationDate];
            NSTimeInterval timeIntervalSinceLastModificationDate = [currentDate timeIntervalSinceDate:lastModificationDate];
            if (timeIntervalSinceLastModificationDate >= OLD_ITEM_DELETION_INTERVAL) {
                [filePathsToRemove addObject:[directory stringByAppendingPathComponent:filename]];
            } else if (timeIntervalSinceLastModificationDate < 0) {
                // Reset the modification date if it's far out in the future
                NSError *resetModificationDateError = nil;
                if (![fileManager setAttributes:@{NSFileModificationDate: currentDate} ofItemAtPath:filePath error:&resetModificationDateError]) {
                    SULog(SULogLevelError, @"Failed to reset modification date of file modified in future: %@", resetModificationDateError.localizedDescription);
                }
            }
        }
        
        [directoryEnumerator skipDescendants];
    }
    
    for (NSString *filename in filePathsToRemove) {
        [fileManager removeItemAtPath:filename error:NULL];
    }
}

+ (NSString * _Nullable)createUniqueDirectoryInDirectory:(NSString *)directory
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *createError = nil;
    if (![fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&createError]) {
        SULog(SULogLevelError, @"Failed to create directory with intermediate components at %@ with error %@", directory, createError);
        return nil;
    }
    
    NSString *templateString = [directory stringByAppendingPathComponent:@"XXXXXXXXX"];
    char buffer[PATH_MAX] = {0};
    if ([templateString getFileSystemRepresentation:buffer maxLength:sizeof(buffer)]) {
        if (mkdtemp(buffer) != NULL) {
            return [[NSString alloc] initWithUTF8String:buffer];
        } else {
            SULog(SULogLevelError, @"Failed to create templated intermediate cache directory using mkdtemp() with error: %d", errno);
        }
    }
    return nil;
}

@end
