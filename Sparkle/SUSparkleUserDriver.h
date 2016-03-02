//
//  SUSparkleUserDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/14/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SUUserDriver.h"

NS_ASSUME_NONNULL_BEGIN

@protocol SUSparkleUserDriverUIDelegate, SUSparkleUserDriverRemoteDelegate;

/*!
 A protocol for Sparkle's user driver's delegate
 
 If you are interested in UI interactions, check out SUSparkleUserDriverUIDelegate
 If you are interested in XPC or remote process communications for efficiency and reliability, check out SUSparkleUserDriverRemoteDelegate
 */
@protocol SUSparkleUserDriverDelegate <SUSparkleUserDriverUIDelegate, SUSparkleUserDriverRemoteDelegate>
@end

/*!
 Sparkle's standard built-in driver for user updater interactions
 */
@interface SUSparkleUserDriver : NSObject <SUUserDriver>

/*!
 Initializes a Sparkle's standard user driver for user update interactions
 
 @param hostBundle The target bundle of the host that is being updated
 @param delegate The delegate to this user driver. Pass nil if you don't want to provide one.
 */
- (instancetype)initWithHostBundle:(NSBundle *)hostBundle delegate:(_Nullable id <SUSparkleUserDriverDelegate>)delegate;

/*!
 Readable and writable property for this user driver's delegate
 */
@property (nonatomic, weak, nullable) id <SUSparkleUserDriverDelegate> delegate;

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

@end

NS_ASSUME_NONNULL_END
