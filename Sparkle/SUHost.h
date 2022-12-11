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

@property (nonatomic, readonly, direct) NSBundle *bundle;

- (instancetype)initWithBundle:(NSBundle *)aBundle __attribute__((objc_direct));

- (instancetype)init NS_UNAVAILABLE;

@property (readonly, nonatomic, copy, direct) NSString *bundlePath;
@property (readonly, nonatomic, copy, direct) NSString *name;
@property (readonly, nonatomic, copy, direct) NSString *version;
@property (readonly, nonatomic, direct) BOOL validVersion;
@property (readonly, nonatomic, copy, direct) NSString *displayVersion;
@property (readonly, nonatomic, direct) SUPublicKeys *publicKeys;

@property (getter=isRunningOnReadOnlyVolume, nonatomic, readonly, direct) BOOL runningOnReadOnlyVolume;
@property (getter=isRunningTranslocated, nonatomic, readonly, direct) BOOL runningTranslocated;
@property (readonly, nonatomic, copy, nullable, direct) NSString *publicDSAKeyFileKey;

- (nullable id)objectForInfoDictionaryKey:(NSString *)key __attribute__((objc_direct));
- (BOOL)boolForInfoDictionaryKey:(NSString *)key __attribute__((objc_direct));
- (nullable id)objectForUserDefaultsKey:(NSString *)defaultName __attribute__((objc_direct));
- (void)setObject:(nullable id)value forUserDefaultsKey:(NSString *)defaultName __attribute__((objc_direct));
- (BOOL)boolForUserDefaultsKey:(NSString *)defaultName __attribute__((objc_direct));
- (void)setBool:(BOOL)value forUserDefaultsKey:(NSString *)defaultName __attribute__((objc_direct));
- (nullable id)objectForKey:(NSString *)key __attribute__((objc_direct));
- (BOOL)boolForKey:(NSString *)key __attribute__((objc_direct));
@end

NS_ASSUME_NONNULL_END
