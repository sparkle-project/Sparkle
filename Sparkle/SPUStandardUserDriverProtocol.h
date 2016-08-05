//
//  SPUStandardUserDriverProtocol.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/5/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SPUStandardUserDriverDelegate;

/*!
 Protocol for Sparkle's standard built-in user driver for updater interactions.
 
 Other user drivers may wish to implement this protocol.
 */
@protocol SPUStandardUserDriverProtocol <NSObject>

/*!
 Readable and writable property for this user driver's delegate
 */
@property (nonatomic, weak, nullable, readonly) id <SPUStandardUserDriverDelegate> delegate;

/*!
 Indicates whether or not an update is in progress as far as the user's perspective is concerned
 
 A typical application may rely on this property for its check for updates menu item validation
 */
@property (nonatomic, readonly) BOOL canCheckForUpdates;

/*!
 Indicates whether or not a currently pending update check will be initiated in the future
 
 This may be useful for deciding if the user driver should be invalidated, when the connection to the updater
 has been interrupted.
 */
@property (nonatomic, readonly) BOOL willInitiateNextUpdateCheck;

/*!
 Indicates whether or not Sparkle's updater has been idling on update checks; i.e, if automatic update checks
 had been disabled the last time the updater checked.
 
 This may be useful for deciding if a connection needs to be immediately resumed or re-created if it has been interrupted.
 See also -willInitiateNextUpdateCheck
 */
@property (nonatomic, readonly) BOOL idlesOnUpdateChecks;

/*!
 Invalidate the current update installation
 
 This stops all behavior for the current update installation. It avoids making any calls or replies to Sparkle's updater.
 Note this does not change the idle state of update checks (i.e, -idlesOnUpdateChecks), but it will invalidate any pending update checks.
 One may want to check if there is a pending update check (i.e, -willInitiateNextUpdateCheck) before making this call to decide if the
 user driver should be invalidated or not
 
 This is appropriate to call when the connection to the updater has been interrupted or invalidated. Note this class is still re-usable
 in the case that the connection should be later resumed.
 */
- (void)invalidate;

@end
