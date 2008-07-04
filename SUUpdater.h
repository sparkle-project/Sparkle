//
//  SUUpdater.h
//  Sparkle
//
//  Created by Andy Matuschak on 1/4/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUUPDATER_H
#define SUUPDATER_H

#import "SUUpdateAlert.h"
#import "SUVersionComparisonProtocol.h"

@class SUUpdateDriver, SUAppcastItem, SUAppcast;
@interface SUUpdater : NSObject {
	NSTimer *checkTimer;
	SUUpdateDriver *driver;
	
	NSBundle *hostBundle;
	IBOutlet id delegate;
}

+ (SUUpdater *)sharedUpdater;

- (void)setDelegate:(id)delegate;

// This IBAction is meant for a main menu item. Hook up any menu item to this action,
// and Sparkle will check for updates and report back its findings verbosely.
- (IBAction)checkForUpdates:sender;

// This kicks off an update meant to be programmatically initiated. That is, it will display no UI unless it actually finds an update,
// in which case it proceeds as usual. If the fully automated updating is turned on, however, this will invoke that behavior, and if an
// update is found, it will be downloaded and prepped for installation.
- (void)checkForUpdatesInBackground;

// This forces an update to begin with a particular driver (see SU*UpdateDriver.h)
- (void)checkForUpdatesWithDriver:(SUUpdateDriver *)driver;

// For non-.app updates:
// Call this when your bundle is loaded to tell Sparkle what to update.
- (void)setHostBundle:(NSBundle *)hostBundle;

// Call this to appropriately reschedule or cancel the update checking timer if preferences for time interval or automatic checks change.
// If you're using a .app, this'll be picked up automatically via NSUserDefaultsController, but for non-.apps, there's no way to observe changes.
- (void)updatePreferencesChanged;

- (BOOL)updateInProgress;
@end

@interface NSObject (SUUpdaterDelegateInformalProtocol)
// This method allows you to add extra parameters to the appcast URL, potentially based on whether or not
// Sparkle will also be sending along the system profile. This method should return an array of dictionaries with the following keys:
- (NSArray *)feedParametersForHostBundle:(NSBundle *)bundle sendingSystemProfile:(BOOL)sendingProfile;

// Use this to override the default behavior for Sparkle prompting the user about automatic update checks.
- (BOOL)shouldPromptForPermissionToCheckForUpdatesToHostBundle:(NSBundle *)bundle;

// Implement this if you want to do some special handling with the appcast once it finishes loading.
- (void)appcastDidFinishLoading:(SUAppcast *)appcast forHostBundle:(NSBundle *)bundle;

// If you're using special logic or extensions in your appcast, implement this to use your own logic for finding
// a valid update, if any, in the given appcast.
- (SUAppcastItem *)bestValidUpdateInAppcast:(SUAppcast *)appcast forHostBundle:(NSBundle *)bundle;

// Sent when a valid update is found by the update driver.
- (void)didFindValidUpdate:(SUAppcastItem *)update toHostBundle:(NSBundle *)bundle;

// Sent when a valid update is not found.
- (void)didNotFindUpdateToHostBundle:(NSBundle *)hb;

// Sent when the user makes a choice in the update alert dialog (install now / remind me later / skip this version).
- (void)userChoseAction:(SUUpdateAlertChoice)action forUpdate:(SUAppcastItem *)update toHostBundle:(NSBundle *)bundle;

// Sent immediately before installing the specified update.
- (void)updateWillInstall:(SUAppcastItem *)update toHostBundle:(NSBundle *)bundle;

// Return YES to delay the relaunch until you do some processing; invoke the given NSInvocation to continue.
- (BOOL)shouldPostponeRelaunchForUpdate:(SUAppcastItem *)update toHostBundle:(NSBundle *)hostBundle untilInvoking:(NSInvocation *)invocation;

// Called immediately before relaunching.
- (void)updaterWillRelaunchApplication;

// This method allows you to provide a custom version comparator.
// If you don't implement this method or return nil, the standard version comparator will be used.
- (id <SUVersionComparison>)versionComparatorForHostBundle:(NSBundle *)hb;

@end

// Define some minimum intervals to avoid DOS-like checking attacks. These are in seconds.
#ifdef DEBUG
#define SU_MIN_CHECK_INTERVAL 60
#else
#define SU_MIN_CHECK_INTERVAL 60*60
#endif

#ifdef DEBUG
#define SU_DEFAULT_CHECK_INTERVAL 60
#else
#define SU_DEFAULT_CHECK_INTERVAL 60*60*24
#endif

#endif
