//
//  SUUpdater.h
//  Sparkle
//
//  Created by Andy Matuschak on 1/4/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUUPDATER_H
#define SUUPDATER_H

#if __has_feature(modules)
@import Foundation;
#else
#import <Foundation/Foundation.h>
#endif
#import "SUExport.h"
#import "SUVersionComparisonProtocol.h"
#import "SUVersionDisplayProtocol.h"
#import "SUUpdaterDelegate.h"

@class SUAppcastItem, SUAppcast;

@protocol SUUpdaterDelegate;

/*!
 The main API in Sparkle for controlling the update mechanism.
 
 This class is used to configure the update paramters as well as manually
 and automatically schedule and control checks for updates.
 
 Note: This class is now deprecated and acts as a thin wrapper around SPUUpdater and SPUStandardUserDriver
 */
__deprecated_msg("Use SPUStandardUpdaterController or SPUUpdater instead")
SU_EXPORT @interface SUUpdater : NSObject

@property (unsafe_unretained, nonatomic) IBOutlet id<SUUpdaterDelegate> delegate;

+ (SUUpdater *)sharedUpdater;
+ (SUUpdater *)updaterForBundle:(NSBundle *)bundle;
- (instancetype)initForBundle:(NSBundle *)bundle;

@property (readonly, nonatomic) NSBundle *hostBundle;
@property (strong, readonly) NSBundle *sparkleBundle;

@property (nonatomic) BOOL automaticallyChecksForUpdates;

@property (nonatomic) NSTimeInterval updateCheckInterval;

/*!
 * The URL of the appcast used to download update information.
 *
 * This property must be called on the main thread.
 */
@property (nonatomic, copy) NSURL *feedURL;

@property (nonatomic, copy) NSString *userAgentString;

@property (nonatomic, copy) NSDictionary *httpHeaders;

@property (nonatomic) BOOL sendsSystemProfile;

@property (nonatomic) BOOL automaticallyDownloadsUpdates;

@property (nonatomic, copy) NSString *decryptionPassword;

/*!
 Explicitly checks for updates and displays a progress dialog while doing so.
 
 This method is meant for a main menu item.
 Connect any menu item to this action in Interface Builder,
 and Sparkle will check for updates and report back its findings verbosely
 when it is invoked.
 */
- (IBAction)checkForUpdates:(id)sender;

/*!
 Checks for updates, but does not display any UI unless an update is found.
 
 This is meant for programmatically initating a check for updates. That is,
 it will display no UI unless it actually finds an update, in which case it
 proceeds as usual.
 
 If the fully automated updating is turned on, however, this will invoke that
 behavior, and if an update is found, it will be downloaded and prepped for
 installation.
 */
- (void)checkForUpdatesInBackground;

/*!
 Returns the date of last update check.
 
 \returns \c nil if no check has been performed.
 */
@property (nonatomic, readonly, copy) NSDate *lastUpdateCheckDate;

/*!
 Begins a "probing" check for updates which will not actually offer to
 update to that version.
 
 However, the delegate methods
 SUUpdaterDelegate::updater:didFindValidUpdate: and
 SUUpdaterDelegate::updaterDidNotFindUpdate: will be called,
 so you can use that information in your UI.
 */
- (void)checkForUpdateInformation;

/*!
 Appropriately schedules or cancels the update checking timer according to
 the preferences for time interval and automatic checks.
 
 This call does not change the date of the next check,
 but only the internal NSTimer.
 */
- (void)resetUpdateCycle;

@property (nonatomic, readonly) BOOL updateInProgress;

@end

// -----------------------------------------------------------------------------
// SUUpdater Notifications for events that might be interesting to more than just the delegate
// The updater will be the notification object
// -----------------------------------------------------------------------------
SU_EXPORT extern NSString *const SUUpdaterDidFinishLoadingAppCastNotification;
SU_EXPORT extern NSString *const SUUpdaterDidFindValidUpdateNotification;
SU_EXPORT extern NSString *const SUUpdaterDidNotFindUpdateNotification;
SU_EXPORT extern NSString *const SUUpdaterWillRestartNotification;
#define SUUpdaterWillRelaunchApplicationNotification SUUpdaterWillRestartNotification;
#define SUUpdaterWillInstallUpdateNotification SUUpdaterWillRestartNotification;

// Key for the SUAppcastItem object in the SUUpdaterDidFindValidUpdateNotification userInfo
SU_EXPORT extern NSString *const SUUpdaterAppcastItemNotificationKey;
// Key for the SUAppcast object in the SUUpdaterDidFinishLoadingAppCastNotification userInfo
SU_EXPORT extern NSString *const SUUpdaterAppcastNotificationKey;

#endif
