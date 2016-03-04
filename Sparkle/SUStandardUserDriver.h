//
//  SUStandardUserDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/14/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SUUserDriver.h"

NS_ASSUME_NONNULL_BEGIN

@protocol SUStandardUserDriverDelegate;

/*!
 Sparkle's standard built-in user driver for updater interactions
 */
@interface SUStandardUserDriver : NSObject <SUUserDriver>

/*!
 Initializes a Sparkle's standard user driver for user update interactions
 
 @param hostBundle The target bundle of the host that is being updated
 @param delegate The delegate to this user driver. Pass nil if you don't want to provide one.
 */
- (instancetype)initWithHostBundle:(NSBundle *)hostBundle delegate:(_Nullable id <SUStandardUserDriverDelegate>)delegate;

/*!
 Readable and writable property for this user driver's delegate
 */
@property (nonatomic, weak, nullable) id <SUStandardUserDriverDelegate> delegate;

/*!
 Indicates whether or not an update is in progress as far as the user is concerned
 
 A typical application may rely on this property for its check for updates menu item validation
 */
@property (nonatomic, readonly, getter=isUpdateInProgress) BOOL updateInProgress;

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
 Dismiss the current update installation
 
 This is appropriate to call when the connection to the updater has been interrupted or invalidated
 before trying to resume or establish a new connection.
 
 This implementation will be dispatched on the main queue.
 
 Note this is also a part of the SUUserDriver protocol that this class implements
 */
- (void)dismissUpdateInstallation;

@end

NS_ASSUME_NONNULL_END
