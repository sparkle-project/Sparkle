//
//  SULocalCacheDirectory.m
//  Sparkle
//
//  Created by Mayur Pawashe on 6/23/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SULocalCacheDirectory.h"

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

@end
