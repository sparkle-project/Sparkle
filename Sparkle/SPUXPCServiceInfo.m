//
//  SUXPCServiceInfo.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUXPCServiceInfo.h"
#import "SUErrors.h"
#import "SUConstants.h"


#include "AppKitPrevention.h"

BOOL SPUXPCServiceExists(NSString *bundleName)
{
    NSBundle *xpcBundle = SPUXPCServiceBundle(bundleName);
    return (xpcBundle != nil);
}

BOOL SPUXPCValidateServiceIfBundleExists(NSString *bundleName, NSBundle *sparkleBundle, NSError * __autoreleasing *error)
{
    NSBundle *xpcBundle = SPUXPCServiceBundle(bundleName);
    if (xpcBundle == nil) {
        return YES;
    }
    
    // Sometimes in debug the short version where we append a git hash is not available,
    // so if our CFBundleVersion == CFBundleShortVersionString, we will compare to CURRENT_PROJECT_VERSION,
    // Otherwise if git hash is correctly appended, we will compare to short version string of Sparkle framework
    NSString *bundleVersion = [xpcBundle objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey];
    NSString *version = [xpcBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    
    NSString *projectVersion = [bundleVersion isEqualToString:version] ? @""CURRENT_PROJECT_VERSION : [sparkleBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    
    if (version == nil || projectVersion == nil || ![version isEqualToString:projectVersion]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInvalidUpdaterError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"XPC Version mismatch. Framework display version is %@ but XPC Service (%@) display version is %@. Bundled XPC Service cannot be used.", projectVersion, xpcBundle.bundlePath, version] }];
        }
        return NO;
    }
    
    return YES;
}

NSBundle * _Nullable SPUXPCServiceBundle(NSString *bundleName)
{
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSURL *executableURL = mainBundle.executableURL;
    if (executableURL == nil) {
        return nil;
    }
    
    NSURL *xpcBundleURL = [[[executableURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent URLByAppendingPathComponent:@"XPCServices"] URLByAppendingPathComponent:bundleName] URLByAppendingPathExtension:@"xpc"];
    
    return [NSBundle bundleWithURL:xpcBundleURL];
}
