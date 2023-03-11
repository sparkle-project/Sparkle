//
//  SUHost.h
//  Sparkle
//
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUPublicKeys;

#ifndef BUILDING_SPARKLE_TESTS
SPU_OBJC_DIRECT_MEMBERS
#endif
@interface SUHost : NSObject

@property (nonatomic, readonly) NSBundle *bundle;

- (instancetype)initWithBundle:(NSBundle *)aBundle;

- (instancetype)init NS_UNAVAILABLE;

@property (readonly, nonatomic, copy) NSString *bundlePath;
@property (readonly, nonatomic, copy) NSString *name;
@property (readonly, nonatomic, copy) NSString *version;
@property (readonly, nonatomic) BOOL validVersion;
@property (readonly, nonatomic, copy) NSString *displayVersion;
@property (readonly, nonatomic) SUPublicKeys *publicKeys;

@property (getter=isRunningOnReadOnlyVolume, nonatomic, readonly) BOOL runningOnReadOnlyVolume;
@property (getter=isRunningTranslocated, nonatomic, readonly) BOOL runningTranslocated;
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
