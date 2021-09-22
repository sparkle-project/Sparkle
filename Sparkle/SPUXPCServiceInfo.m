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

#if DEBUG
        // Post install scripts for appending git hash info to CFBundleShortVersionString are too unreliable to verify for debug/development
        // Fortunately debug builds of Sparkle are not usable in a production environment
    (void)sparkleBundle; // Mark parameter as used
#else
        // Make sure the display versions of Sparkle and the XPC bundle match
        // These versions may contain a git hash identifier if built from the Sparkle repository
    NSString *sparkleDisplayVersion = [sparkleBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *xpcDisplayVersion = [xpcBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];

    if (sparkleDisplayVersion == nil || xpcDisplayVersion == nil || ![sparkleDisplayVersion isEqualToString:xpcDisplayVersion]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInvalidUpdaterError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"XPC Version mismatch. Framework display version is %@ but XPC Service (%@) display version is %@. Bundled XPC Service cannot be used.", sparkleDisplayVersion, xpcBundle.bundlePath, xpcDisplayVersion] }];
        }
        return NO;
    }
#endif

        // Make sure the bundle versions of Sparkle and the XPC bundle match
    NSString *xpcBundleVersion = [xpcBundle objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey];

    if (xpcBundleVersion == nil || ![xpcBundleVersion isEqualToString:@""CURRENT_PROJECT_VERSION]) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInvalidUpdaterError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"XPC Version mismatch. Framework bundle version is %@ but XPC Service (%@) bundle version is %@. Bundled XPC Service cannot be used.", @""CURRENT_PROJECT_VERSION, xpcBundle.bundlePath, xpcBundleVersion] }];
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
