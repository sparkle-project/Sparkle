//
//  SUUpdatePermissionResponse.h
//  Sparkle
//
//  Created by Mayur Pawashe on 12/26/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

/*!
 This class represents a response for permission to check updates.
 */
@interface SUUpdatePermissionResponse : NSObject

/*!
 Initializes a new update permission response instance.
 
 @param automaticUpdateChecks Flag for whether to allow automatic update checks.
 @param sendSystemProfile Flag for if system profile information should be sent to the server hosting the appcast.
 */
- (instancetype)initWithAutomaticUpdateChecks:(BOOL)automaticUpdateChecks sendSystemProfile:(BOOL)sendSystemProfile;

/*!
 A read-only property indicating whether automatic update checks are allowed or not.
 */
@property (nonatomic, readonly) BOOL automaticUpdateChecks;

/*!
 A read-only property indicating if system profile should be sent or not.
 */
@property (nonatomic, readonly) BOOL sendSystemProfile;

@end
