//
//  SUHost.h
//  Sparkle
//
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUPublicKeys;

@interface SUHost : NSObject

@property (strong, readonly) NSBundle *bundle;

- (instancetype)initWithBundle:(NSBundle *)aBundle;
@property (readonly, copy) NSString *bundlePath;
@property (readonly, copy) NSString *name;
@property (readonly, copy) NSString *version;
@property (readonly, copy) NSString *displayVersion;
@property (readonly) SUPublicKeys *publicKeys;

@property (getter=isRunningOnReadOnlyVolume, readonly) BOOL runningOnReadOnlyVolume;
@property (getter=isRunningTranslocated, readonly) BOOL runningTranslocated;
@property (readonly, nonatomic, copy, nullable) NSString *publicDSAKeyFileKey;

- (nullable id)objectForInfoDictionaryKey:(NSString *)key;
- (BOOL)boolForInfoDictionaryKey:(NSString *)key;
- (nullable id)objectForUserDefaultsKey:(NSString *)defaultName;
- (void)setObject:(nullable id)value forUserDefaultsKey:(NSString *)defaultName;
- (BOOL)boolForUserDefaultsKey:(NSString *)defaultName;
- (void)setBool:(BOOL)value forUserDefaultsKey:(NSString *)defaultName;
- (nullable id)objectForKey:(NSString *)key;
- (BOOL)boolForKey:(NSString *)key;
@end

NS_ASSUME_NONNULL_END
