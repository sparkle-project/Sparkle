//
//  SULocalCacheDirectory.m
//  Sparkle
//
//  Created by Mayur Pawashe on 6/23/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SULocalCacheDirectory.h"
#import "SULog.h"

static NSTimeInterval OLD_ITEM_DELETION_INTERVAL = 86400 * 10; // 10 days

@implementation SULocalCacheDirectory

// If we support sandboxing this component in the future, it is important to note this may return a different path
// For this reason, this method should not be a part of SUHost because its behavior depends on what kind of process it's being invoked from
+ (NSString *)cachePathForBundleIdentifier:(NSString *)bundleIdentifier
{
    NSURL *cacheURL = [[NSFileManager defaultManager] URLForDirectory:NSCachesDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:NULL];
    assert(cacheURL != nil);
    
    NSString *resultPath = [[[cacheURL URLByAppendingPathComponent:bundleIdentifier] URLByAppendingPathComponent:@SPARKLE_BUNDLE_IDENTIFIER] path];
    assert(resultPath != nil);
    
    return resultPath;
}

+ (void)removeOldItemsInDirectory:(NSString *)directory
{
    NSMutableArray<NSString *> *filePathsToRemove = [NSMutableArray array];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:directory]) {
        NSDirectoryEnumerator *directoryEnumerator = [fileManager enumeratorAtPath:directory];
        NSDate *currentDate = [NSDate date];
        for (NSString *filename in directoryEnumerator)
        {
            NSDictionary<NSString *, id> *fileAttributes = [fileManager attributesOfItemAtPath:[directory stringByAppendingPathComponent:filename] error:NULL];
            if (fileAttributes != nil)
            {
                NSDate *lastModificationDate = fileAttributes[NSFileModificationDate];
                if ([currentDate timeIntervalSinceDate:lastModificationDate] >= OLD_ITEM_DELETION_INTERVAL)
                {
                    [filePathsToRemove addObject:[directory stringByAppendingPathComponent:filename]];
                }
            }
            
            [directoryEnumerator skipDescendants];
        }
        
        for (NSString *filename in filePathsToRemove)
        {
            [fileManager removeItemAtPath:filename error:NULL];
        }
    }
}

+ (NSString * _Nullable)createUniqueDirectoryInDirectory:(NSString *)directory
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *createError = nil;
    if (![fileManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&createError]) {
        SULog(@"Failed to create directory with intermediate components at %@ with error %@", directory, createError);
        return nil;
    }
    
    NSString *templateString = [directory stringByAppendingPathComponent:@"XXXXXXXXX"];
    char buffer[PATH_MAX] = {0};
    if ([templateString getFileSystemRepresentation:buffer maxLength:sizeof(buffer)]) {
        if (mkdtemp(buffer) != NULL) {
            return [[NSString alloc] initWithUTF8String:buffer];
        }
    }
    return nil;
}

@end
