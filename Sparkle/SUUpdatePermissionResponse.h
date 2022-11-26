//
//  SUUpdatePermissionResponse.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/8/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Sparkle/SUExport.h>

NS_ASSUME_NONNULL_BEGIN

/**
 This class represents a response for permission to check updates.
*/
SU_EXPORT @interface SUUpdatePermissionResponse : NSObject<NSSecureCoding>

/**
 Initializes a new update permission response instance.
 
 @param automaticUpdateChecks Flag to enable automatic update checks.
 @param sendSystemProfile Flag for if system profile information should be sent to the server hosting the appcast.
 */
- (instancetype)initWithAutomaticUpdateChecks:(BOOL)automaticUpdateChecks sendSystemProfile:(BOOL)sendSystemProfile;

/**
 Initializes a new update permission response instance.
 
 @param automaticUpdateChecks Flag to enable automatic update checks.
 @param automaticallyDownloadUpdates Flag to enable automatic downloading and installing of updates. If this is nil, then no response was made for this option.
 @param sendSystemProfile Flag for if system profile information should be sent to the server hosting the appcast.
 */
- (instancetype)initWithAutomaticUpdateChecks:(BOOL)automaticUpdateChecks automaticallyDownloadUpdates:(NSNumber * _Nullable)automaticallyDownloadUpdates sendSystemProfile:(BOOL)sendSystemProfile;

/*
 Use -initWithAutomaticUpdateChecks:sendSystemProfile: instead.
 */
- (instancetype)init NS_UNAVAILABLE;

/**
 A read-only property indicating whether automatic update checks are allowed or not.
 */
@property (nonatomic, readonly) BOOL automaticUpdateChecks;

/**
 A read-only property indicating whether automatic downloading and installing of updates is on.
 */
@property (nonatomic, readonly, nullable) NSNumber *automaticallyDownloadUpdates;

/**
 A read-only property indicating if system profile should be sent or not.
 */
@property (nonatomic, readonly) BOOL sendSystemProfile;

@end

NS_ASSUME_NONNULL_END
