//
//  SULocalCacheDirectory.h
//  Sparkle
//
//  Created by Mayur Pawashe on 6/23/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SULocalCacheDirectory : NSObject

// Returns a path to a suitable cache directory to create specifically for Sparkle
// Intermediate directories to this path may not exist yet
// This path may depend on the type of running process,
// such that sandboxed vs non-sandboxed processes could yield different paths
+ (NSString *)cachePathForBundleIdentifier:(NSString *)bundleIdentifier;

@end

NS_ASSUME_NONNULL_END
