//
//  SUUpdater.h
//  Sparkle
//
//  Created by Andy Matuschak on 1/4/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUUPDATER_H
#define SUUPDATER_H

#import <Foundation/Foundation.h>
#import "SUExport.h"
#import "SUUserDriver.h"

@class SUAppcastItem, SUAppcast;

@protocol SUUpdaterDelegate;

/*!
    The main API in Sparkle for controlling the update mechanism.

    This class is used to configure the update paramters as well as manually
    and automatically schedule and control checks for updates.
 */
SU_EXPORT @interface SUUpdater : NSObject

/*!
 * Initializes a new SUUpdater instance
 *
 * Update checks will start a short delay after initialization. This is to prevent the updater starting work before an application may have finished launching.
 *
 * Note that this is a normal initializer and doesn't implement the singleton pattern (i.e, instances aren't cached, so no surprises)
 * Hence you shouldn't create multiple live instances that target the same bundle.
 * However, this also means that updater instances can be deallocated, and that they will be torn down properly
 *
 * Related: See SUUpdaterController which wraps a SUUpdater instance and is suitable for instantiating in nib files
 *
 * @param hostBundle The bundle that should be targetted for updating. This must not be nil.
 * @param userDriver The user driver that Sparkle uses for user update interaction
 * @param delegate The delegate for SUUpdater. This may be nil.
 *
 * This must be called on the main thread.
 */
- (instancetype)initWithHostBundle:(NSBundle *)hostBundle userDriver:(id <SUUserDriver>)userDriver delegate:(id <SUUpdaterDelegate>)delegate;

@property (weak, readonly) id<SUUpdaterDelegate> delegate;
@property (nonatomic, readonly) id<SUUserDriver> userDriver;

@property (readonly, strong) NSBundle *hostBundle;
@property (strong, readonly) NSBundle *sparkleBundle;

@property (nonatomic) BOOL automaticallyChecksForUpdates;

@property (nonatomic) NSTimeInterval updateCheckInterval;

/*!
 * The URL of the appcast used to download update information.
 *
 * This property must be called on the main thread.
 */
@property (copy) NSURL *feedURL;

@property (nonatomic, copy) NSString *userAgentString;

@property (copy) NSDictionary *httpHeaders;

@property (nonatomic) BOOL sendsSystemProfile;

@property (nonatomic) BOOL automaticallyDownloadsUpdates;

/*!
    Checks for updates, and displays progress while doing so
 
    This is meant for users initiating an update check
 */
- (void)checkForUpdates;

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
@property (readonly, copy) NSDate *lastUpdateCheckDate;

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
    but only the internal timer.
 */
- (void)resetUpdateCycle;

@end

#endif
