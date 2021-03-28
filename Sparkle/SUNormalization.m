//
//  SUNormalization.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/26/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SUNormalization.h"


#include "AppKitPrevention.h"

NSString *SUNormalizedInstallationPath(SUHost *host)
{
    NSBundle *bundle = host.bundle;
    assert(bundle != nil);
   
    NSString * baseBundleName = [host objectForInfoDictionaryKey:@"SUBundleName"];
   
    if (baseBundleName == nil) {
        baseBundleName = [host objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleNameKey];
    }
    
    NSString *normalizedAppPath = [[[bundle bundlePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.%@", baseBundleName, [[bundle bundlePath] pathExtension]]];

    // Roundtrip string through fileSystemRepresentation to ensure it uses filesystem's Unicode normalization
    // rather than arbitrary Unicode form from Info.plist - #1017
    NSString *unicodeNormalizedPath = [NSString stringWithUTF8String:[normalizedAppPath fileSystemRepresentation]];
    if (unicodeNormalizedPath != nil) {
        return unicodeNormalizedPath;
    } else {
        return normalizedAppPath;
    }
}
