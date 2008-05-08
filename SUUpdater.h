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
	NSTimeInterval checkInterval;
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
