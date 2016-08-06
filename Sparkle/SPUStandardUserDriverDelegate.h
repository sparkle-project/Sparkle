//
//  SPUStandardUserDriverDelegate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/3/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUExport.h"

@protocol SUVersionDisplay;

/*!
 A protocol for Sparkle's standard user driver's delegate
 
 This includes methods related to UI interactions and XPC/remote process communication.
 */
SU_EXPORT @protocol SPUStandardUserDriverDelegate <NSObject>

@optional

/*!
 Called before showing a modal alert window,
 to give the opportunity to hide attached windows that may get in the way.
 */
- (void)userDriverWillShowModalAlert;

/*!
 Called after showing a modal alert window,
 to give the opportunity to hide attached windows that may get in the way.
 */
- (void)userDriverDidShowModalAlert;

/*!
 Returns an object that formats version numbers for display to the user.
 If you don't implement this method or return \c nil,
 the standard version formatter will be used.
 */
- (_Nullable id <SUVersionDisplay>)userDriverRequestsVersionDisplayer;

/*!
 Asks whether or not the delegate is responsible for initiating updater checks.
 
 The user driver uses this to decide whether or not it should be the one initiating update checks.
 If the delegate wants to initiate update checks, then the user driver lets the updater know it shouldn't
 wait for a response from the user driver. When the user driver and updater live in separate processes,
 having a delegate implement this can be more efficient for the system and therefore is encouraged.
 
 @return Returns if the delegate is responsible for initiating update checks. If the delegate returns YES,
 then the delegate must also implement -userDriverRequestsInitatingUpdateCheck which is when the delegate should
 initiate update checks.
 */
- (BOOL)userDriverRequestsResponsibilityForInitiatingUpdateCheck;

/*!
 Called when user driver tells the delegate to initiate an update check
 
 This is called if the delegate returned YES from -userDriverRequestsResponsibilityForInitiatingUpdateCheck
 
 The delegate will have to find a pathway to tell the SUUpdater instance to check for updates, that
 does not go through the user driver. See -userDriverRequestsResponsibilityForInitiatingUpdateCheck as to why
 a delegate may want to implement this.
 */
- (void)userDriverRequestsInitatingUpdateCheck;

@end
