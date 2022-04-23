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

+ (NSString *)systemVersionString
{
    NSOperatingSystemVersion version = self.operatingSystemVersion;
    return [NSString stringWithFormat:@"%ld.%ld.%ld", (long)version.majorVersion, (long)version.minorVersion, (long)version.patchVersion];
}

@end
