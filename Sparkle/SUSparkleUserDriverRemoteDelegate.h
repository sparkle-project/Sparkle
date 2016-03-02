//
//  SUSparkleUserDriverRemoteDelegate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/2/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SUUserDriver;

/*!
 A delegate protocol for Sparkle's user driver related to efficiency and reliablity when Sparkle's updater lives in a separate process
 */
@protocol SUSparkleUserDriverRemoteDelegate <NSObject>

@optional

/*!
 Asks whether or not the delegate is responsible for initiating updater checks.
 
 The user driver uses this to decide whether or not it should be the one initiating update checks.
 If the delegate wants to initiate update checks, then the user driver lets the updater know it shouldn't
 wait for a response from the user driver. When the user driver and updater live in separate processes,
 having a delegate implement this can be more efficient for the system and therefore is encouraged.
 
 @return Returns if the delegate is responsible for initiating update checks. If the delegate returns YES,
 then the delegate must also implement -initiateUpdateCheckForUserDriver: which is when the delegate should
 initiate update checks.
 
 @param userDriver The user driver instance.
 */
- (BOOL)responsibleForInitiatingUpdateCheckForUserDriver:(id <SUUserDriver>)userDriver;

/*!
 Called when user driver tells the delegate to initiate an update check
 
 This is called if the delegate returned YES from -responsibleForInitiatingUpdateCheckForUserDriver:
 
 The delegate will have to find a pathway to tell the SUUpdater instance to check for updates, that
 does not go through the user driver. See -responsibleForInitiatingUpdateCheckForUserDriver: as to why
 a delegate may want to implement this.
 
 @param userDriver The user driver instance.
 */
- (void)initiateUpdateCheckForUserDriver:(id <SUUserDriver>)userDriver;

/*!
 Asks whether or not the delegate is responsible for letting the user driver know when the application is about to terminate
 
 This is necessary to implement when automatic updates are possible and when the updater and user driver live in separate processes.
 
 See -[SUSparkleUserDriver sendApplicationTerminationSignal] for more details on how to follow up
 
 @param userDriver The user driver instance.
 */
- (BOOL)responsibleForSignalingApplicationTerminationForUserDriver:(id <SUUserDriver>)userDriver;

@end

NS_ASSUME_NONNULL_END
