//
//  SUOperatingSystem.m
//  Sparkle
//
//  Copyright © 2015 Sparkle Project. All rights reserved.
//

#import "SUOperatingSystem.h"


#include "AppKitPrevention.h"

@implementation SUOperatingSystem

+ (NSOperatingSystemVersion)operatingSystemVersion
{
    return [[NSProcessInfo processInfo] operatingSystemVersion];
}

+ (BOOL)isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion)version
{
    const NSOperatingSystemVersion systemVersion = self.operatingSystemVersion;
    if (systemVersion.majorVersion == version.majorVersion) {
        if (systemVersion.minorVersion == version.minorVersion) {
            return systemVersion.patchVersion >= version.patchVersion;
        }
        return systemVersion.minorVersion >= version.minorVersion;
    }
    return systemVersion.majorVersion >= version.majorVersion;
}

+ (NSString *)systemVersionString
{
    NSOperatingSystemVersion version = self.operatingSystemVersion;
    return [NSString stringWithFormat:@"%ld.%ld.%ld", (long)version.majorVersion, (long)version.minorVersion, (long)version.patchVersion];
}

@end
