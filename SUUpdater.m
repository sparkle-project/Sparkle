//
//  SUUpdater.m
//  Sparkle
//
//  Created by Andy Matuschak on 1/4/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUUpdater.h"

#import "SUHost.h"
#import "SUUpdatePermissionPrompt.h"

#import "SUAutomaticUpdateDriver.h"
#import "SUProbingUpdateDriver.h"
#import "SUUserInitiatedUpdateDriver.h"
#import "SUScheduledUpdateDriver.h"
#import "SUConstants.h"
#import "SULog.h"
#import "SUCodeSigningVerifier.h"
#include <SystemConfiguration/SystemConfiguration.h>


@interface SUUpdater (Private)
- (id)initForBundle:(NSBundle *)bundle;
- (void)startUpdateCycle;
- (void)checkForUpdatesWithDriver:(SUUpdateDriver *)updateDriver;
- (BOOL)automaticallyDownloadsUpdates;
- (void)scheduleNextUpdateCheck;
- (void)registerAsObserver;
- (void)unregisterAsObserver;
- (void)updateDriverDidFinish:(NSNotification *)note;
- (NSURL *)parameterizedFeedURL;

-(void)	notifyWillShowModalAlert;
-(void)	notifyDidShowModalAlert;

@end

@implementation SUUpdater

#pragma mark Initialization

static NSMutableDictionary *sharedUpdaters = nil;
static NSString * const SUUpdaterDefaultsObservationContext = @"SUUpdaterDefaultsObservationContext";

+ (SUUpdater *)sharedUpdater
{
	return [self updaterForBundle:[NSBundle mainBundle]];
}

// SUUpdater has a singleton for each bundle. We use the fact that NSBundle instances are also singletons, so we can use them as keys. If you don't trust that you can also use the identifier as key
+ (SUUpdater *)updaterForBundle:(NSBundle *)bundle
{
    if (bundle == nil) bundle = [NSBundle mainBundle];
	id updater = [sharedUpdaters objectForKey:[NSValue valueWithNonretainedObject:bundle]];
	if (updater == nil)
		updater = [[[[self class] alloc] initForBundle:bundle] autorelease];
	return updater;
}

// This is the designated initializer for SUUpdater, important for subclasses
- (id)initForBundle:(NSBundle *)bundle
{
	self = [super init];
    if (bundle == nil) bundle = [NSBundle mainBundle];
	
	// Register as observer straight away to avoid exceptions on -dealloc when -unregisterAsObserver is called:
	if (self)
		[self registerAsObserver];
	
	id updater = [sharedUpdaters objectForKey:[NSValue valueWithNonretainedObject:bundle]];
    if (updater)
	{
		[self release];
		self = [updater retain];
	}
	else if (self)
	{
		if (sharedUpdaters == nil)
            sharedUpdaters = [[NSMutableDictionary alloc] init];
        [sharedUpdaters setObject:self forKey:[NSValue valueWithNonretainedObject:bundle]];
        host = [[SUHost alloc] initWithBundle:bundle];
		
#if !ENDANGER_USERS_WITH_INSECURE_UPDATES
		// Saving-the-developer-from-a-stupid-mistake-check:
        BOOL hasPublicDSAKey = [host publicDSAKey] != nil;
        BOOL isMainBundle = [bundle isEqualTo:[NSBundle mainBundle]];
        BOOL hostIsCodeSigned = [SUCodeSigningVerifier hostApplicationIsCodeSigned];
        if (!isMainBundle && !hasPublicDSAKey) {
            [self notifyWillShowModalAlert];
            NSRunAlertPanel(@"Insecure update error!", @"For security reasons, you need to sign your updates with a DSA key. See Sparkle's documentation for more information.", @"OK", nil, nil);
            [self notifyDidShowModalAlert];
        } else if (isMainBundle && !(hasPublicDSAKey || hostIsCodeSigned)) {
            [self notifyWillShowModalAlert];
            NSRunAlertPanel(@"Insecure update error!", @"For security reasons, you need to code sign your application or sign your updates with a DSA key. See Sparkle's documentation for more information.", @"OK", nil, nil);
            [self notifyDidShowModalAlert];
        }
#endif
        // This runs the permission prompt if needed, but never before the app has finished launching because the runloop won't run before that
        [self performSelector:@selector(startUpdateCycle) withObject:nil afterDelay:0];
	}
	return self;
}


// This will be used when the updater is instantiated in a nib such as MainMenu
- (id)init
{
    return [self initForBundle:[NSBundle mainBundle]];
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@, %@>", [self class], [host bundlePath], [host installationPath]]; }


-(void)	notifyWillShowModalAlert
{
	if( [delegate respondsToSelector: @selector(updaterWillShowModalAlert:)] )
		[delegate updaterWillShowModalAlert: self];
}


-(void)	notifyDidShowModalAlert
{
	if( [delegate respondsToSelector: @selector(updaterDidShowModalAlert:)] )
		[delegate updaterDidShowModalAlert: self];
}


- (void)startUpdateCycle
{
    BOOL shouldPrompt = NO;
    
	// If the user has been asked about automatic checks, don't bother prompting
	if ([host objectForUserDefaultsKey:SUEnableAutomaticChecksKey])
    {
        shouldPrompt = NO;
    }
    // Does the delegate want to take care of the logic for when we should ask permission to update?
    else if ([delegate respondsToSelector:@selector(updaterShouldPromptForPermissionToCheckForUpdates:)])
    {
        shouldPrompt = [delegate updaterShouldPromptForPermissionToCheckForUpdates:self];
    }	
    // Has he been asked already? And don't ask if the host has a default value set in its Info.plist.
    else if ([host objectForKey:SUEnableAutomaticChecksKey] == nil)
    {
        if ([host objectForUserDefaultsKey:SUEnableAutomaticChecksKeyOld])
            [self setAutomaticallyChecksForUpdates:[host boolForUserDefaultsKey:SUEnableAutomaticChecksKeyOld]];
        // Now, we don't want to ask the user for permission to do a weird thing on the first launch.
        // We wait until the second launch, unless explicitly overridden via SUPromptUserOnFirstLaunchKey.
        else if (![host objectForKey:SUPromptUserOnFirstLaunchKey])
        {
            if ([host boolForUserDefaultsKey:SUHasLaunchedBeforeKey] == NO)
                [host setBool:YES forUserDefaultsKey:SUHasLaunchedBeforeKey];
            else
                shouldPrompt = YES;
        }
        else
            shouldPrompt = YES;
    }
    
    if (shouldPrompt)
    {
		NSArray *profileInfo = [host systemProfile];
		// Always say we're sending the system profile here so that the delegate displays the parameters it would send.
		if ([delegate respondsToSelector:@selector(feedParametersForUpdater:sendingSystemProfile:)]) 
			profileInfo = [profileInfo arrayByAddingObjectsFromArray:[delegate feedParametersForUpdater:self sendingSystemProfile:YES]];
        [SUUpdatePermissionPrompt promptWithHost:host systemProfile:profileInfo delegate:self];
        // We start the update checks and register as observer for changes after the prompt finishes
	}
    else 
    {
        // We check if the user's said they want updates, or they haven't said anything, and the default is set to checking.
        [self scheduleNextUpdateCheck];
    }
}

- (void)updatePermissionPromptFinishedWithResult:(SUPermissionPromptResult)result
{
	[self setAutomaticallyChecksForUpdates:(result == SUAutomaticallyCheck)];
    // Schedule checks, but make sure we ignore the delayed call from KVO
	[self resetUpdateCycle];
}

- (void)updateDriverDidFinish:(NSNotification *)note
{
	if ([note object] == driver && [driver finished])
	{
		[driver release]; driver = nil;
		[self scheduleNextUpdateCheck];
    }
}

- (NSDate *)lastUpdateCheckDate
{
	return [host objectForUserDefaultsKey:SULastCheckTimeKey];
}

- (void)scheduleNextUpdateCheck
{	
	if (checkTimer)
	{
		[checkTimer invalidate];
		[checkTimer release];		// UK 2009-03-16 Timer is non-repeating, may have invalidated itself, so we had to retain it.
		checkTimer = nil;
	}
	if (![self automaticallyChecksForUpdates]) return;
	
	// How long has it been since last we checked for an update?
	NSDate *lastCheckDate = [self lastUpdateCheckDate];
	if (!lastCheckDate) { lastCheckDate = [NSDate distantPast]; }
	NSTimeInterval intervalSinceCheck = [[NSDate date] timeIntervalSinceDate:lastCheckDate];
	
	// Now we want to figure out how long until we check again.
	NSTimeInterval delayUntilCheck, updateCheckInterval = [self updateCheckInterval];
	if (updateCheckInterval < SU_MIN_CHECK_INTERVAL)
		updateCheckInterval = SU_MIN_CHECK_INTERVAL;
	if (intervalSinceCheck < updateCheckInterval)
		delayUntilCheck = (updateCheckInterval - intervalSinceCheck); // It hasn't been long enough.
	else
		delayUntilCheck = 0; // We're overdue! Run one now.
	checkTimer = [[NSTimer scheduledTimerWithTimeInterval:delayUntilCheck target:self selector:@selector(checkForUpdatesInBackground) userInfo:nil repeats:NO] retain];		// UK 2009-03-16 Timer is non-repeating, may have invalidated itself, so we had to retain it.
}


-(void)	putFeedURLIntoDictionary: (NSMutableDictionary*)theDict	// You release this.
{
	[theDict setObject: [self feedURL] forKey: @"feedURL"];
}

-(void)	checkForUpdatesInBgReachabilityCheckWithDriver: (SUUpdateDriver*)inDriver /* RUNS ON ITS OWN THREAD */
{
	NS_DURING
		// This method *must* be called on its own thread. SCNetworkReachabilityCheckByName
		//	can block, and it can be waiting a long time on slow networks, and we
		//	wouldn't want to beachball the main thread for a background operation.
		// We could use asynchronous reachability callbacks, but those aren't
		//	reliable enough and can 'get lost' sometimes, which we don't want.
		
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		SCNetworkConnectionFlags flags = 0;
		BOOL isNetworkReachable = YES;
		
		// Don't perform automatic checks on unconnected laptops or dial-up connections that aren't online:
		NSMutableDictionary*		theDict = [NSMutableDictionary dictionary];
		[self performSelectorOnMainThread: @selector(putFeedURLIntoDictionary:) withObject: theDict waitUntilDone: YES];	// Get feed URL on main thread, it's not safe to call elsewhere.
		
		const char *hostname = [[[theDict objectForKey: @"feedURL"] host] cStringUsingEncoding: NSUTF8StringEncoding];
		SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, hostname);
        Boolean reachabilityResult = NO;
        // If the feed's using a file:// URL, we won't be able to use reachability.
        if (reachability != NULL) {
            SCNetworkReachabilityGetFlags(reachability, &flags);
            CFRelease(reachability);
        }
		
		if( reachabilityResult )
		{
			BOOL reachable =	(flags & kSCNetworkFlagsReachable)				== kSCNetworkFlagsReachable;
			BOOL automatic =	(flags & kSCNetworkFlagsConnectionAutomatic)	== kSCNetworkFlagsConnectionAutomatic;
			BOOL local =		(flags & kSCNetworkFlagsIsLocalAddress)			== kSCNetworkFlagsIsLocalAddress;
			
			//NSLog(@"reachable = %s, automatic = %s, local = %s", (reachable?"YES":"NO"), (automatic?"YES":"NO"), (local?"YES":"NO"));
			
			if( !(reachable || automatic || local) )
				isNetworkReachable = NO;
		}
		
        // If the network's not reachable, we pass a nil driver into checkForUpdatesWithDriver, which will then reschedule the next update so we try again later.    
        [self performSelectorOnMainThread: @selector(checkForUpdatesWithDriver:) withObject: isNetworkReachable ? inDriver : nil waitUntilDone: NO];
		
		[pool release];
	NS_HANDLER
		SULog(@"UNCAUGHT EXCEPTION IN UPDATE CHECK TIMER: %@",[localException reason]);
		// Don't propagate the exception beyond here. In Carbon apps that would trash the stack.
	NS_ENDHANDLER
}


- (void)checkForUpdatesInBackground
{
	// Background update checks should only happen if we have a network connection.
	//	Wouldn't want to annoy users on dial-up by establishing a connection every
	//	hour or so:
	SUUpdateDriver *	theUpdateDriver = [[[([self automaticallyDownloadsUpdates] ? [SUAutomaticUpdateDriver class] : [SUScheduledUpdateDriver class]) alloc] initWithUpdater:self] autorelease];
	
	[NSThread detachNewThreadSelector: @selector(checkForUpdatesInBgReachabilityCheckWithDriver:) toTarget: self withObject: theUpdateDriver];
}


- (BOOL)mayUpdateAndRestart
{
	return( !delegate || ![delegate respondsToSelector: @selector(updaterShouldRelaunchApplication:)] || [delegate updaterShouldRelaunchApplication: self] );
}

- (IBAction)checkForUpdates: (id)sender
{
	[self checkForUpdatesWithDriver:[[[SUUserInitiatedUpdateDriver alloc] initWithUpdater:self] autorelease]];
}

- (void)checkForUpdateInformation
{
	[self checkForUpdatesWithDriver:[[[SUProbingUpdateDriver alloc] initWithUpdater:self] autorelease]];
}

- (void)checkForUpdatesWithDriver:(SUUpdateDriver *)d
{
	if ([self updateInProgress]) { return; }
	if (checkTimer) { [checkTimer invalidate]; [checkTimer release]; checkTimer = nil; }		// UK 2009-03-16 Timer is non-repeating, may have invalidated itself, so we had to retain it.
	
	SUClearLog();
	SULog( @"===== %@ =====", [[NSFileManager defaultManager] displayNameAtPath: [[NSBundle mainBundle] bundlePath]] );
		
	[self willChangeValueForKey:@"lastUpdateCheckDate"];
	[host setObject:[NSDate date] forUserDefaultsKey:SULastCheckTimeKey];
	[self didChangeValueForKey:@"lastUpdateCheckDate"];
	
    if( [delegate respondsToSelector: @selector(updaterMayCheckForUpdates:)] && ![delegate updaterMayCheckForUpdates: self] )
	{
		[self scheduleNextUpdateCheck];
		return;
	}
    	
    driver = [d retain];
    
    // If we're not given a driver at all, just schedule the next update check and bail.
    if (!driver)
    {
        [self scheduleNextUpdateCheck];
        return;
    }
    
	NSURL*	theFeedURL = [self parameterizedFeedURL];
	if( theFeedURL )	// Use a NIL URL to cancel quietly.
		[driver checkForUpdatesAtURL: theFeedURL host:host];
	else
		[driver abortUpdate];
}

- (void)registerAsObserver
{
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateDriverDidFinish:) name:SUUpdateDriverFinishedNotification object:nil];
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self forKeyPath:[@"values." stringByAppendingString:SUScheduledCheckIntervalKey] options:0 context:SUUpdaterDefaultsObservationContext];
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self forKeyPath:[@"values." stringByAppendingString:SUEnableAutomaticChecksKey] options:0 context:SUUpdaterDefaultsObservationContext];
}

- (void)unregisterAsObserver
{
	@try
	{
		[[NSNotificationCenter defaultCenter] removeObserver:self];
		[[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self forKeyPath:[@"values." stringByAppendingString:SUScheduledCheckIntervalKey]];
		[[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self forKeyPath:[@"values." stringByAppendingString:SUEnableAutomaticChecksKey]];
	}
	@catch (NSException *e)
	{
		NSLog(@"Sparkle Error: [SUUpdater unregisterAsObserver] called, but the updater wasn't registered as an observer.");
	}
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (context == SUUpdaterDefaultsObservationContext)
    {
        // Allow a small delay, because perhaps the user or developer wants to change both preferences. This allows the developer to interpret a zero check interval as a sign to disable automatic checking.
        // Or we may get this from the developer and from our own KVO observation, this will effectively coalesce them.
        [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(resetUpdateCycle) object:nil];
        [self performSelector:@selector(resetUpdateCycle) withObject:nil afterDelay:1];
    }
    else
    {
    	[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)resetUpdateCycle
{
    [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(resetUpdateCycle) object:nil];
    [self scheduleNextUpdateCheck];
}

- (void)setAutomaticallyChecksForUpdates:(BOOL)automaticallyCheckForUpdates
{
	[host setBool:automaticallyCheckForUpdates forUserDefaultsKey:SUEnableAutomaticChecksKey];
	// Hack to support backwards compatibility with older Sparkle versions, which supported
	// disabling updates by setting the check interval to 0.
    if (automaticallyCheckForUpdates && [self updateCheckInterval] == 0)
        [self setUpdateCheckInterval:SU_DEFAULT_CHECK_INTERVAL];
    [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(resetUpdateCycle) object:nil];
	// Provide a small delay in case multiple preferences are being updated simultaneously.
    [self performSelector:@selector(resetUpdateCycle) withObject:nil afterDelay:1];
}

- (BOOL)automaticallyChecksForUpdates
{
	// Don't automatically update when the check interval is 0, to be compatible with 1.1 settings.
    if ([self updateCheckInterval] == 0)
        return NO;	
	return [host boolForKey:SUEnableAutomaticChecksKey];
}

- (void)setAutomaticallyDownloadsUpdates:(BOOL)automaticallyUpdates
{
	[host setBool:automaticallyUpdates forUserDefaultsKey:SUAutomaticallyUpdateKey];
}

- (BOOL)automaticallyDownloadsUpdates
{
	// If the SUAllowsAutomaticUpdatesKey exists and is set to NO, return NO.
	if ([host objectForInfoDictionaryKey:SUAllowsAutomaticUpdatesKey] && [host boolForInfoDictionaryKey:SUAllowsAutomaticUpdatesKey] == NO)
		return NO;
	
	// Otherwise, automatically downloading updates is allowed. Does the user want it?
	return [host boolForUserDefaultsKey:SUAutomaticallyUpdateKey];
}

- (void)setFeedURL:(NSURL *)feedURL
{
	[host setObject:[feedURL absoluteString] forUserDefaultsKey:SUFeedURLKey];
}

- (NSURL *)feedURL // *** MUST BE CALLED ON MAIN THREAD ***
{
	// A value in the user defaults overrides one in the Info.plist (so preferences panels can be created wherein users choose between beta / release feeds).
	NSString *appcastString = [host objectForKey:SUFeedURLKey];
	if( [delegate respondsToSelector: @selector(feedURLStringForUpdater:)] )
		appcastString = [delegate feedURLStringForUpdater: self];
	if (!appcastString) // Can't find an appcast string!
		[NSException raise:@"SUNoFeedURL" format:@"You must specify the URL of the appcast as the SUFeedURL key in either the Info.plist or the user defaults!"];
	NSCharacterSet* quoteSet = [NSCharacterSet characterSetWithCharactersInString: @"\"\'"]; // Some feed publishers add quotes; strip 'em.
	NSString*	castUrlStr = [appcastString stringByTrimmingCharactersInSet:quoteSet];
	if( !castUrlStr || [castUrlStr length] == 0 )
		return nil;
	else
		return [NSURL URLWithString: castUrlStr];
}

- (void)setUserAgentString:(NSString *)userAgent
{
	if (customUserAgentString == userAgent)
		return;

	[customUserAgentString release];
	customUserAgentString = [userAgent copy];
}

- (NSString *)userAgentString
{
	if (customUserAgentString)
		return customUserAgentString;

	NSString *version = [SPARKLE_BUNDLE objectForInfoDictionaryKey:@"CFBundleVersion"];
	NSString *userAgent = [NSString stringWithFormat:@"%@/%@ Sparkle/%@", [host name], [host displayVersion], version ? version : @"?"];
	NSData *cleanedAgent = [userAgent dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
	return [[[NSString alloc] initWithData:cleanedAgent encoding:NSASCIIStringEncoding] autorelease];
}

- (void)setSendsSystemProfile:(BOOL)sendsSystemProfile
{
	[host setBool:sendsSystemProfile forUserDefaultsKey:SUSendProfileInfoKey];
}

- (BOOL)sendsSystemProfile
{
	return [host boolForUserDefaultsKey:SUSendProfileInfoKey];
}

- (NSURL *)parameterizedFeedURL
{
	NSURL *baseFeedURL = [self feedURL];
	
	// Determine all the parameters we're attaching to the base feed URL.
	BOOL sendingSystemProfile = [self sendsSystemProfile];

	// Let's only send the system profiling information once per week at most, so we normalize daily-checkers vs. biweekly-checkers and the such.
	NSDate *lastSubmitDate = [host objectForUserDefaultsKey:SULastProfileSubmitDateKey];
	if(!lastSubmitDate)
	    lastSubmitDate = [NSDate distantPast];
	const NSTimeInterval oneWeek = 60 * 60 * 24 * 7;
	sendingSystemProfile &= (-[lastSubmitDate timeIntervalSinceNow] >= oneWeek);

	NSArray *parameters = [NSArray array];
	if ([delegate respondsToSelector:@selector(feedParametersForUpdater:sendingSystemProfile:)])
		parameters = [parameters arrayByAddingObjectsFromArray:[delegate feedParametersForUpdater:self sendingSystemProfile:sendingSystemProfile]];
	if (sendingSystemProfile)
	{
		parameters = [parameters arrayByAddingObjectsFromArray:[host systemProfile]];
		[host setObject:[NSDate date] forUserDefaultsKey:SULastProfileSubmitDateKey];
	}
	if ([parameters count] == 0) { return baseFeedURL; }
	
	// Build up the parameterized URL.
	NSMutableArray *parameterStrings = [NSMutableArray array];
	NSEnumerator *profileInfoEnumerator = [parameters objectEnumerator];
	NSDictionary *currentProfileInfo;
	while ((currentProfileInfo = [profileInfoEnumerator nextObject]))
		[parameterStrings addObject:[NSString stringWithFormat:@"%@=%@", [[[currentProfileInfo objectForKey:@"key"] description] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding], [[[currentProfileInfo objectForKey:@"value"] description] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
	
	NSString *separatorCharacter = @"?";
	if ([baseFeedURL query])
		separatorCharacter = @"&"; // In case the URL is already http://foo.org/baz.xml?bat=4
	NSString *appcastStringWithProfile = [NSString stringWithFormat:@"%@%@%@", [baseFeedURL absoluteString], separatorCharacter, [parameterStrings componentsJoinedByString:@"&"]];
	
	// Clean it up so it's a valid URL
	return [NSURL URLWithString:appcastStringWithProfile];
}

- (void)setUpdateCheckInterval:(NSTimeInterval)updateCheckInterval
{
	[host setObject:[NSNumber numberWithDouble:updateCheckInterval] forUserDefaultsKey:SUScheduledCheckIntervalKey];
	if (updateCheckInterval == 0) // For compatibility with 1.1's settings.
		[self setAutomaticallyChecksForUpdates:NO];
	[[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(resetUpdateCycle) object:nil];
	
	// Provide a small delay in case multiple preferences are being updated simultaneously.
	[self performSelector:@selector(resetUpdateCycle) withObject:nil afterDelay:1];
}

- (NSTimeInterval)updateCheckInterval
{
	// Find the stored check interval. User defaults override Info.plist.
	NSNumber *intervalValue = [host objectForKey:SUScheduledCheckIntervalKey];
	if (intervalValue)
		return [intervalValue doubleValue];
	else
		return SU_DEFAULT_CHECK_INTERVAL;
}

- (void)dealloc
{
	[self unregisterAsObserver];
	[host release];
	if (checkTimer) { [checkTimer invalidate]; [checkTimer release]; checkTimer = nil; }		// UK 2009-03-16 Timer is non-repeating, may have invalidated itself, so we had to retain it.
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

- (BOOL)updateInProgress
{
	return driver && ([driver finished] == NO);
}

- (id)delegate { return delegate; }
- (NSBundle *)hostBundle { return [host bundle]; }

@end
