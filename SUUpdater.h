//
//  SUUpdater.h
//  Sparkle
//
//  Created by Andy Matuschak on 1/4/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUUPDATER_H
#define SUUPDATER_H

@class SUUpdateDriver;
@interface SUUpdater : NSObject {
	NSTimer *checkTimer;
	SUUpdateDriver *driver;
	
	NSBundle *hostBundle;
	id delegate;
}

- (void)setHostBundle:(NSBundle *)hostBundle;
- (void)setDelegate:(id)delegate;

// This IBAction is meant for a main menu item. Hook up any menu item to this action,
// and Sparkle will check for updates and report back its findings verbosely.
- (IBAction)checkForUpdates:sender;

// This forces an update to begin with a particular driver (see SU*UpdateDriver.h)
- (void)checkForUpdatesWithDriver:(SUUpdateDriver *)driver;

- (BOOL)updateInProgress;

@end

@interface NSObject (SUUpdaterDelegateInformalProtocol)
// This method allows you to add extra parameters to the appcast URL, potentially based on whether or not
// Sparkle will also be sending along the system profile. This method should return an array of dictionaries with the following keys:
- (NSArray *)feedParametersForUpdater:(SUUpdater *)updater sendingSystemProfile:(BOOL)sendingProfile;

// Use this to override the default behavior for Sparkle prompting the user about automatic update checks.
- (BOOL)shouldPromptForPermissionToCheckForUpdates;

// Implement this if you want to do some special handling with the appcast once it finishes loading.
- (void)appcastDidFinishLoading:(SUAppcast *)appcast;

// If you're using special logic or extensions in your appcast, implement this to use your own logic for finding
// a valid update, if any, in the given appcast.
- (SUAppcastItem *)bestValidUpdateInAppcast:(SUAppcast *)appcast;

// Sent when a valid update is found by the update driver.
- (void)didFindValidUpdate:(SUAppcastItem *)update;

// Sent when the user makes a choice in the update alert dialog (install now / remind me later / skip this version).
- (void)userChoseAction:(SUUpdateAlertChoice)action forUpdate:(SUAppcastItem *)update;

// Sent immediately before installing the specified update.
- (void)updateWillInstall:(SUAppcastItem *)update;

// Return YES to delay the relaunch until you do some processing; invoke the given NSInvocation to continue.
- (BOOL)shouldPostponeRelaunchForUpdate:(SUAppcastItem *)update untilInvoking:(NSInvocation *)invocation;

// Called immediately before relaunching.
- (void)updaterWillRelaunchApplication;

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
