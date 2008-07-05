//
//  SUUpdater.m
//  Sparkle
//
//  Created by Andy Matuschak on 1/4/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "Sparkle.h"
#import "SUUpdater.h"

@interface SUUpdater (Private)
- (NSArray *)feedParameters;
- (BOOL)automaticallyUpdates;
- (BOOL)shouldScheduleUpdateCheck;
- (void)scheduleNextUpdateCheck;
- (NSTimeInterval)checkInterval;
- (NSURL *)feedURL;
@end

@implementation SUUpdater

#pragma mark Initialization

static SUUpdater *sharedUpdater = nil;

// SUUpdater's a singleton now! And I'm enforcing it!
// This will probably break the world if you try to write a Sparkle-enabled plugin for a Sparkle-enabled app.
+ (SUUpdater *)sharedUpdater
{
	if (sharedUpdater == nil)
		sharedUpdater = [[[self class] alloc] init];
	return sharedUpdater;
}

- (id)init
{
	self = [super init];
	if (sharedUpdater)
	{
		[self release];
		self = sharedUpdater;
	}
	else if (self != nil)
	{
		sharedUpdater = self;
		[self setHostBundle:[NSBundle mainBundle]];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidFinishLaunching:) name:NSApplicationDidFinishLaunchingNotification object:NSApp];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(driverDidFinish:) name:SUUpdateDriverFinishedNotification object:nil];
		[[NSUserDefaultsController sharedUserDefaultsController] addObserver:self forKeyPath:[@"values." stringByAppendingString:SUScheduledCheckIntervalKey] options:0 context:NULL];
		[[NSUserDefaultsController sharedUserDefaultsController] addObserver:self forKeyPath:[@"values." stringByAppendingString:SUEnableAutomaticChecksKey] options:0 context:NULL];
	}
	return self;
}

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
	// If the user has been asked about automatic checks and said no, get out of here.
	if ([[SUUserDefaults standardUserDefaults] objectForKey:SUEnableAutomaticChecksKey] &&
		[[SUUserDefaults standardUserDefaults] boolForKey:SUEnableAutomaticChecksKey] == NO) { return; }
	
	// Does the delegate want to take care of the logic for when we should ask permission to update?
	if ([delegate respondsToSelector:@selector(shouldPromptForPermissionToCheckForUpdatesToHostBundle:)])
	{
		if ([delegate shouldPromptForPermissionToCheckForUpdatesToHostBundle:hostBundle])
			[SUUpdatePermissionPrompt promptWithHostBundle:hostBundle delegate:self];
	}	
	// Has he been asked already? And don't ask if the host has a default value set in its Info.plist.
	else if ([[SUUserDefaults standardUserDefaults] objectForKey:SUEnableAutomaticChecksKey] == nil &&
		[hostBundle objectForInfoDictionaryKey:SUEnableAutomaticChecksKey] == nil)
	{
		if ([[SUUserDefaults standardUserDefaults] objectForKey:SUEnableAutomaticChecksKeyOld])
			[[SUUserDefaults standardUserDefaults] setBool:[[SUUserDefaults standardUserDefaults] boolForKey:SUEnableAutomaticChecksKeyOld] forKey:SUEnableAutomaticChecksKey];
		// Now, we don't want to ask the user for permission to do a weird thing on the first launch.
		// We wait until the second launch.
		else if ([[SUUserDefaults standardUserDefaults] boolForKey:SUHasLaunchedBeforeKey] == NO)
			[[SUUserDefaults standardUserDefaults] setBool:YES forKey:SUHasLaunchedBeforeKey];
		else
			[SUUpdatePermissionPrompt promptWithHostBundle:hostBundle delegate:self];
	}
	
	// We check if the user's said they want updates, or they haven't said anything, and the default is set to checking.
	[self scheduleNextUpdateCheck];
}

- (void)updatePermissionPromptFinishedWithResult:(SUPermissionPromptResult)result
{
	[[SUUserDefaults standardUserDefaults] setBool:(result == SUAutomaticallyCheck) forKey:SUEnableAutomaticChecksKey];
	[self scheduleNextUpdateCheck];
}

- (void)scheduleNextUpdateCheck
{	
	if (checkTimer)
	{
		[checkTimer invalidate];
		checkTimer = nil;
	}
	if (![self shouldScheduleUpdateCheck]) return;
	
	// How long has it been since last we checked for an update?
	NSDate *lastCheckDate = [[SUUserDefaults standardUserDefaults] objectForKey:SULastCheckTimeKey];
	if (!lastCheckDate) { lastCheckDate = [NSDate distantPast]; }
	NSTimeInterval intervalSinceCheck = [[NSDate date] timeIntervalSinceDate:lastCheckDate];
	
	// Now we want to figure out how long until we check again.
	NSTimeInterval delayUntilCheck;
	if (intervalSinceCheck < [self checkInterval])
		delayUntilCheck = ([self checkInterval] - intervalSinceCheck); // It hasn't been long enough.
	else
		delayUntilCheck = 0; // We're overdue! Run one now.
	checkTimer = [NSTimer scheduledTimerWithTimeInterval:delayUntilCheck target:self selector:@selector(checkForUpdatesInBackground) userInfo:nil repeats:NO];
}

- (void)checkForUpdatesInBackground
{
	[self checkForUpdatesWithDriver:[[[([self automaticallyUpdates] ? [SUAutomaticUpdateDriver class] : [SUScheduledUpdateDriver class]) alloc] init] autorelease]];
}

- (IBAction)checkForUpdates:sender
{
	[self checkForUpdatesWithDriver:[[[SUUserInitiatedUpdateDriver alloc] init] autorelease]];
}

- (void)checkForUpdatesWithDriver:(SUUpdateDriver *)d
{
	if ([self updateInProgress]) { return; }
	if (checkTimer) { [checkTimer invalidate]; checkTimer = nil; }
	
	driver = [d retain];
	if ([driver delegate] == nil) { [driver setDelegate:delegate]; }
	[driver checkForUpdatesAtURL:[self feedURL] hostBundle:hostBundle];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (object == [NSUserDefaultsController sharedUserDefaultsController] && ([keyPath hasSuffix:SUScheduledCheckIntervalKey] || [keyPath hasSuffix:SUEnableAutomaticChecksKey]))
	{
		[self updatePreferencesChanged];
	}
	else
	{
		[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
	}
}

- (void)updatePreferencesChanged
{
	[self scheduleNextUpdateCheck];
}

- (BOOL)shouldScheduleUpdateCheck
{
	// Breaking this down for readability:
	// If the user says he wants automatic update checks, let's do it.
	if ([[SUUserDefaults standardUserDefaults] boolForKey:SUEnableAutomaticChecksKey] == YES)
		return YES;
	// If the user hasn't said anything, but the developer says we should do it, let's do it.
	if ([[SUUserDefaults standardUserDefaults] objectForKey:SUEnableAutomaticChecksKey] == nil &&
	  [[hostBundle objectForInfoDictionaryKey:SUEnableAutomaticChecksKey] boolValue] == YES)
		return YES;
	return NO; // Otherwise, don't bother.
}

- (BOOL)automaticallyUpdates
{
	// If the SUAllowsAutomaticUpdatesKey exists and is set to NO, return NO.
	if ([hostBundle objectForInfoDictionaryKey:SUAllowsAutomaticUpdatesKey] &&
		[[hostBundle objectForInfoDictionaryKey:SUAllowsAutomaticUpdatesKey] boolValue] == NO)
		return NO;
	
	// If we're not using DSA signatures, we aren't going to trust any updates automatically.
	if ([[hostBundle objectForInfoDictionaryKey:SUExpectsDSASignatureKey] boolValue] != YES)
		return NO;
	
	// If there's no setting, or it's set to no, we're not automatically updating.
	if ([[SUUserDefaults standardUserDefaults] boolForKey:SUAutomaticallyUpdateKey] != YES)
		return NO;
	
	return YES; // Otherwise, we're good to go.
}

- (NSURL *)_baseFeedURL
{
	// A value in the user defaults overrides one in the Info.plist (so preferences panels can be created wherein users choose between beta / release feeds).
	NSString *appcastString = [[SUUserDefaults standardUserDefaults] objectForKey:SUFeedURLKey];
	if (!appcastString)
		appcastString = [hostBundle objectForInfoDictionaryKey:SUFeedURLKey];
	if (!appcastString) // Can't find an appcast string!
		[NSException raise:@"SUNoFeedURL" format:@"You must specify the URL of the appcast as the SUFeedURLKey in either the Info.plist or the user defaults!"];
	NSCharacterSet* quoteSet = [NSCharacterSet characterSetWithCharactersInString: @"\"\'"]; // Some feed publishers add quotes; strip 'em.
	return [NSURL URLWithString:[appcastString stringByTrimmingCharactersInSet:quoteSet]] ;
}

- (NSURL *)feedURL
{
	NSURL *baseFeedURL = [self _baseFeedURL];
	
	// Determine all the parameters we're attaching to the base feed URL.
	BOOL sendingSystemProfile = ([[SUUserDefaults standardUserDefaults] boolForKey:SUSendProfileInfoKey] == YES);
	NSArray *parameters = [NSArray array];
	if ([delegate respondsToSelector:@selector(feedParametersForHostBundle:sendingSystemProfile:)])
		parameters = [parameters arrayByAddingObjectsFromArray:[delegate feedParametersForHostBundle:hostBundle sendingSystemProfile:sendingSystemProfile]];
	if (sendingSystemProfile)
		parameters = [parameters arrayByAddingObjectsFromArray:[hostBundle systemProfile]];
	if (parameters == nil || [parameters count] == 0) { return baseFeedURL; }
	
	// Build up the parameterized URL.
	NSMutableArray *parameterStrings = [NSMutableArray array];
	NSEnumerator *profileInfoEnumerator = [parameters objectEnumerator];
	NSDictionary *currentProfileInfo;
	while ((currentProfileInfo = [profileInfoEnumerator nextObject]))
		[parameterStrings addObject:[NSString stringWithFormat:@"%@=%@", [currentProfileInfo objectForKey:@"key"], [currentProfileInfo objectForKey:@"value"]]];
	
	NSString *appcastStringWithProfile = [NSString stringWithFormat:@"%@?%@", [baseFeedURL absoluteString], [parameterStrings componentsJoinedByString:@"&"]];
	
	// Clean it up so it's a valid URL
	return [NSURL URLWithString:[appcastStringWithProfile stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
}

- (NSTimeInterval)checkInterval
{
	NSTimeInterval checkInterval = 0;
	// Find the stored check interval. User defaults override Info.plist.
	if ([[SUUserDefaults standardUserDefaults] objectForKey:SUScheduledCheckIntervalKey])
		checkInterval = [[[SUUserDefaults standardUserDefaults] objectForKey:SUScheduledCheckIntervalKey] doubleValue];
	else if ([hostBundle objectForInfoDictionaryKey:SUScheduledCheckIntervalKey])
		checkInterval = [[hostBundle objectForInfoDictionaryKey:SUScheduledCheckIntervalKey] doubleValue];
	
	if (checkInterval < SU_MIN_CHECK_INTERVAL) // This can also mean one that isn't set.
		checkInterval = SU_DEFAULT_CHECK_INTERVAL;	
	return checkInterval;
}

- (void)dealloc
{
	[hostBundle release];
	if (checkTimer) { [checkTimer invalidate]; }
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
	if ([item action] == @selector(checkForUpdates:))
		return ![self updateInProgress];
	return YES;
}

- (void)setDelegate:aDelegate
{
	delegate = aDelegate;
}

- (void)setHostBundle:(NSBundle *)hb
{
	if (hostBundle == hb) return;
	[hostBundle release];
	hostBundle = [hb retain];
	[[SUUserDefaults standardUserDefaults] setIdentifier:[hostBundle bundleIdentifier]];
}

- (BOOL)updateInProgress
{
	return driver && ([driver finished] == NO);
}

- (void)driverDidFinish:(NSNotification *)notification
{
	if ([notification object] != driver) return;
	[driver release];
	driver = nil;
	[self scheduleNextUpdateCheck];
}

@end
