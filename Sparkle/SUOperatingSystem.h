//
//  SUOperatingSystem.h
//  Sparkle
//
//  Copyright © 2015 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

#if __MAC_OS_X_VERSION_MAX_ALLOWED < 101000
typedef struct {
    NSInteger majorVersion;
    NSInteger minorVersion;
    NSInteger patchVersion;
} NSOperatingSystemVersion;
#endif

@interface SUOperatingSystem : NSObject

+ (NSOperatingSystemVersion)operatingSystemVersion;
+ (BOOL)isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion)version;
+ (NSString *)systemVersionString;

@end
