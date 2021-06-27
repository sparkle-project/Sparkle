//
//  SUAppcastItem.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUAPPCASTITEM_H
#define SUAPPCASTITEM_H

#if __has_feature(modules)
#if __has_warning("-Watimport-in-framework-header")
#pragma clang diagnostic ignored "-Watimport-in-framework-header"
#endif
@import Foundation;
#else
#import <Foundation/Foundation.h>
#endif

#ifdef BUILDING_SPARKLE_TESTS
// Ignore incorrect warning
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wquoted-include-in-framework-header"
#import "SUExport.h"
#pragma clang diagnostic pop
#else
#import <Sparkle/SUExport.h>
#endif

@class SUSignatures;
@class SPUAppcastItemState;

NS_ASSUME_NONNULL_BEGIN

SU_EXPORT @interface SUAppcastItem : NSObject<NSSecureCoding>
@property (copy, readonly, nullable) NSString *title;
@property (copy, readonly, nullable) NSString *dateString;
@property (copy, readonly, nullable) NSDate *date;
@property (copy, readonly, nullable) NSString *itemDescription;
@property (strong, readonly, nullable) NSURL *releaseNotesURL;
@property (strong, readonly, nullable) SUSignatures *signatures;
@property (copy, readonly, nullable) NSString *minimumSystemVersion;
@property (copy, readonly, nullable) NSString *maximumSystemVersion;
@property (strong, readonly, nullable) NSURL *fileURL;
@property (nonatomic, readonly) uint64_t contentLength;
@property (copy, readonly) NSString *versionString;
@property (copy, readonly, nullable) NSString *osString;
@property (copy, readonly, nullable) NSString *displayVersionString;
@property (copy, readonly, nullable) NSDictionary *deltaUpdates;
@property (strong, readonly, nullable) NSURL *infoURL;
@property (copy, readonly, nullable) NSNumber* phasedRolloutInterval;
@property (nonatomic, copy, readonly) NSString *installationType;
@property (copy, readonly, nullable) NSString *minimumAutoupdateVersion;
@property (nonatomic, readonly, nullable) NSString *channel;

@property (getter=isDeltaUpdate, readonly) BOOL deltaUpdate;
@property (getter=isCriticalUpdate, readonly) BOOL criticalUpdate;
@property (getter=isMajorUpgrade, readonly) BOOL majorUpgrade;
@property (getter=isMacOsUpdate, readonly) BOOL macOsUpdate;
@property (getter=isInformationOnlyUpdate, readonly) BOOL informationOnlyUpdate;

@property (nonatomic, readonly) BOOL minimumOperatingSystemVersionIsOK;
@property (nonatomic, readonly) BOOL maximumOperatingSystemVersionIsOK;

// Returns the dictionary representing the appcast item; this might be useful later for extensions.
@property (readonly, copy) NSDictionary *propertiesDictionary;

- (instancetype)init NS_UNAVAILABLE;

// Deprecated initializers
- (nullable instancetype)initWithDictionary:(NSDictionary *)dict __deprecated_msg("Properties that depend on the system or application version are not supported when used with this initializer. The designated initializer is available in SUAppcastItem+Private.h. Please first explore other APIs or contact us to describe your use case.");
- (nullable instancetype)initWithDictionary:(NSDictionary *)dict failureReason:(NSString * _Nullable __autoreleasing *_Nullable)error __deprecated_msg("Properties that depend on the system or application version are not supported when used with this initializer. The designated initializer is available in SUAppcastItem+Private.h. Please first explore other APIs or contact us to describe your use case.");
- (nullable instancetype)initWithDictionary:(NSDictionary *)dict relativeToURL:(NSURL * _Nullable)appcastURL failureReason:(NSString * _Nullable __autoreleasing *_Nullable)error __deprecated_msg("Properties that depend on the system or application version are not supported when used with this initializer. The designated initializer is available in SUAppcastItem+Private.h. Please first explore other APIs or contact us to describe your use case.");

@end

NS_ASSUME_NONNULL_END

#endif
