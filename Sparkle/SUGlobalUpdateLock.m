//
//  SUGlobalUpdateFileLock.m
//  Sparkle
//
//  Created by Bibhas Acharya on 7/12/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

#import "SUGlobalUpdateLock.h"
#import "SULog.h"


@implementation SUGlobalUpdateLock

+ (SUGlobalUpdateLock *)sharedLock
{
    static dispatch_once_t once;
    static SUGlobalUpdateLock *sharedInstance = nil;
    dispatch_once(&once, ^{
        sharedInstance = [self new];
    });
    return sharedInstance;
}

- (void)lock
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *fileLockPath = [self fileLockPath];
    
    BOOL success = [fileManager createFileAtPath:fileLockPath contents:nil attributes:nil];
    if (!success) {
        SULog(SULogLevelDefault, @"Couldn't create lockfile at: %@", fileLockPath);
    }
}

- (void)unlock
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *fileLockPath = [self fileLockPath];
    
    if ([fileManager fileExistsAtPath:fileLockPath]) {
        NSError *error = nil;
        [fileManager removeItemAtPath:fileLockPath error:&error];
        if (error != nil) {
            SULog(SULogLevelError, @"Couldn't remove lockfile at: %@ [%@]", fileLockPath, [error localizedDescription]);
        }
    }
}

- (NSString *)identifier
{
    NSString *resp = [[NSBundle mainBundle] bundleIdentifier];
    if (resp == nil) {
        // If there's no bundle identifier, use the executable path
        resp = [[[NSBundle mainBundle] executablePath] stringByReplacingOccurrencesOfString:@"/" withString:@"."];
    }
    return resp;
}

- (NSString *)fileLockPath
{
    return [NSString stringWithFormat:@"/private/tmp/%@.Sparkle.pid",  [self identifier]];
}

@end
