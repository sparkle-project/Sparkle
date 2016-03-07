//
//  SUStandardUserDriverProtocol.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/5/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SUStandardUserDriverDelegate;

/*!
 Protocol for Sparkle's standard built-in user driver for updater interactions.
 
 Other user drivers may wish to implement this protocol.
 */
@protocol SUStandardUserDriver <NSObject>

/*!
 Readable and writable property for this user driver's delegate
 */
@property (nonatomic, weak, nullable, readonly) id <SUStandardUserDriverDelegate> delegate;

/*!
 Indicates whether or not an update is in progress as far as the user's perspective is concerned
 
 A typical application may rely on this property for its check for updates menu item validation
 */
@property (nonatomic, readonly, getter=isUpdateInProgress) BOOL updateInProgress;

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
 Send a signal to the user driver that the user application should terminate.
 
 This should only be invoked if the user driver's delegate says it's responsible for signaling application termination,
 and this should only be called from NSApplicationDelegate's applicationShouldTerminate: method.
 
 This is particularly useful when the user driver and updater live in separate processes, and the updater
 wants to install an automatic update on termination. If the updater is in a separate process, that means
 we may have to defer application termination a bit until the updater is ready to launch its auto updater.
 
 @return The NSApplication termination reply. Use this as a return value to NSApplicationDelegate's applicationShouldTerminate:
 */
- (NSApplicationTerminateReply)sendApplicationTerminationSignal;

/*!
 Terminate the current application after sending a termination signal
 
 This should only be invoked by the user driver's delegate if the -sendApplicationTerminationSignal message has been sent prior.
 For this user driver's delegate, invoking this is appropriate when the application's termination has been delayed, and the connection
 to the updater has been invalidated or interrupted -- in which case the updater can no longer tell the user driver when to finish terminating.
 
 This implementation will be dispatched on the main queue.
 
 Note this is also a part of the SUUserDriver protocol that this class implements
 */
- (void)terminateApplication;

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
