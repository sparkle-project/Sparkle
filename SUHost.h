//
//  SUHost.h
//  Sparkle
//
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "Sparkle.h"

@interface SUHost : NSObject
{
	NSBundle *bundle;
}

+ (NSString *)systemVersionString;

- (id)initWithBundle:(NSBundle *)aBundle;
- (NSBundle *)bundle;
- (NSString *)bundlePath;
- (NSString *)name;
- (NSString *)version;
- (NSString *)displayVersion;
- (NSImage *)icon;
- (BOOL)isRunningOnReadOnlyVolume;
- (BOOL)isBackgroundApplication;
- (NSString *)publicDSAKey;
- (NSArray *)systemProfile;

- (id)objectForInfoDictionaryKey:(NSString *)key;
- (BOOL)boolForInfoDictionaryKey:(NSString *)key;
- (id)objectForUserDefaultsKey:(NSString *)defaultName;
- (void)setObject:(id)value forUserDefaultsKey:(NSString *)defaultName;
- (BOOL)boolForUserDefaultsKey:(NSString *)defaultName;
- (void)setBool:(BOOL)value forUserDefaultsKey:(NSString *)defaultName;
- (id)objectForKey:(NSString *)key;
- (BOOL)boolForKey:(NSString *)key;
@end
