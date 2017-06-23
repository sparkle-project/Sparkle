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

#if __has_feature(objc_class_property)
@property (class, readonly) NSOperatingSystemVersion operatingSystemVersion;
#else
+ (NSOperatingSystemVersion)operatingSystemVersion;
#endif

+ (BOOL)isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion)version;

#if __has_feature(objc_class_property)
@property (class, readonly) NSString *systemVersionString;
#else
+ (NSString *)systemVersionString;
#endif

@end
