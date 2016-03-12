//
//  SUStandardUserDriverRemoteDelegate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/2/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/*!
 A delegate protocol for Sparkle's standard user driver related to efficiency and reliablity when Sparkle's updater lives in a separate process
 */
@protocol SUStandardUserDriverRemoteDelegate <NSObject>

@optional

/*!
 Asks whether or not the delegate is responsible for initiating updater checks.
 
 The user driver uses this to decide whether or not it should be the one initiating update checks.
 If the delegate wants to initiate update checks, then the user driver lets the updater know it shouldn't
 wait for a response from the user driver. When the user driver and updater live in separate processes,
 having a delegate implement this can be more efficient for the system and therefore is encouraged.
 
 @return Returns if the delegate is responsible for initiating update checks. If the delegate returns YES,
 then the delegate must also implement -initiateUpdateCheck which is when the delegate should
 initiate update checks.
 */
- (BOOL)responsibleForInitiatingUpdateCheck;

/*!
 Called when user driver tells the delegate to initiate an update check
 
 This is called if the delegate returned YES from -responsibleForInitiatingUpdateCheck
 
 The delegate will have to find a pathway to tell the SUUpdater instance to check for updates, that
 does not go through the user driver. See -responsibleForInitiatingUpdateCheck as to why
 a delegate may want to implement this.
 */
- (void)initiateUpdateCheck;

/*!
 Asks whether or not the delegate is responsible for letting the user driver know when the application is about to terminate
 
 This is necessary to implement when automatic updates are possible and when the updater and user driver live in separate processes.
 
 See -[SUStandardUserDriver sendApplicationTerminationSignal] for more details on how to follow up
 */
- (BOOL)responsibleForSignalingApplicationTermination;

@end

NS_ASSUME_NONNULL_END
