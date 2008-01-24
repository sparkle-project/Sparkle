//
//  SUUpdater.h
//  Sparkle
//
//  Created by Andy Matuschak on 1/4/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SUUPDATER_H
#define SUUPDATER_H

// Before you use Sparkle in your app, you must set SUFeedURL in Info.plist to the
// address of the appcast on your webserver. If you don't already have an 
// appcast, please see the Sparkle documentation to learn about how to set one up.

// .zip, .dmg, .tar, .tbz, .tgz archives are supported at this time.

@class SUAppcastItem, SUUpdateAlert, SUStatusController;
@interface SUUpdater : NSObject {
	SUAppcastItem *updateItem;
	
	SUStatusController *statusController;
	SUUpdateAlert *updateAlert;
	
	NSURLDownload *downloader;
	NSString *downloadPath;
			
	NSTimer *checkTimer;
	NSTimeInterval checkInterval;	
	
	BOOL userInitiated;
	BOOL updateInProgress;
	
	NSBundle *hostBundle;
	id delegate;
}

- (void)setHostBundle:(NSBundle *)hostBundle;
- (void)setDelegate:(id)delegate;

// This IBAction is meant for a main menu item. Hook up any menu item to this action,
// and Sparkle will check for updates and report back its findings verbosely.
- (IBAction)checkForUpdates:sender;

// This method is similar to the above, but it's intended for updates initiated by
// the computer instead of by the user. It does not alert the user when he is up to date,
// and it remains silent about network errors in fetching the feed. This is what you
// want to call to update programmatically; only use checkForUpdates: with buttons and menu items.
- (void)checkForUpdatesInBackground;

// This method allows you to schedule a check to run every time interval. You probably don't want
// to call this directly: if you set a SUScheduledCheckInterval key in Info.plist or
// the user defaults, Sparkle will set this up for you automatically on startup. You might
// just want to call this every time the user changes the setting in the preferences.
- (void)scheduleCheckWithInterval:(NSTimeInterval)interval;

+ (NSString *)systemVersionString; // Returns the current system's version.

@end

@interface NSObject (SUUpdaterDelegateInformalProtocol)
/*!
    @method     
    @abstract   Delegate method for host apps to define additional feed parameters
	@discussion This method allows you to add extra parameters to the appcast URL, potentially based on whether or not Sparkle will also be sending along the system profile. This method should return an array of dictionaries with the  following keys:
 
 key: 		The key to be used  when reporting data to the server
 
 visibleKey:	Alternate version of key to be used in UI displays of profile information
 
 value:		Value to be used when reporting data to the server
 
 visibleValue:	Alternate version of value to be used in UI displays of profile information.
*/


- (NSArray *)feedParametersForUpdater:(SUUpdater *)updater sendingSystemProfile:(BOOL)sendingProfile;
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
