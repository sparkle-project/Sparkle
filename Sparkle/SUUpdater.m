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

NSString *const SUUpdaterDidFinishLoadingAppCastNotification = @"SUUpdaterDidFinishLoadingAppCastNotification";
NSString *const SUUpdaterDidFindValidUpdateNotification = @"SUUpdaterDidFindValidUpdateNotification";
NSString *const SUUpdaterDidNotFindUpdateNotification = @"SUUpdaterDidNotFindUpdateNotification";
NSString *const SUUpdaterWillRestartNotification = @"SUUpdaterWillRestartNotificationName";
NSString *const SUUpdaterAppcastItemNotificationKey = @"SUUpdaterAppcastItemNotificationKey";
NSString *const SUUpdaterAppcastNotificationKey = @"SUUpdaterAppCastNotificationKey";

@interface SUUpdater () <SUUpdatePermissionPromptDelegate>
@property (strong) NSTimer *checkTimer;
@property (strong) NSBundle *sparkleBundle;

- (instancetype)initForBundle:(NSBundle *)bundle;
- (void)startUpdateCycle;
- (void)checkForUpdatesWithDriver:(SUUpdateDriver *)updateDriver;
- (void)scheduleNextUpdateCheck;
- (void)registerAsObserver;
- (void)unregisterAsObserver;
- (void)updateDriverDidFinish:(NSNotification *)note;
@property (readonly, copy) NSURL *parameterizedFeedURL;

- (void)notifyWillShowModalAlert;
- (void)notifyDidShowModalAlert;

@property (strong) SUUpdateDriver *driver;
@property (strong) SUHost *host;

@end

@implementation SUUpdater

@synthesize delegate;
@synthesize checkTimer;
@synthesize userAgentString = customUserAgentString;
@synthesize httpHeaders;
@synthesize driver;
@synthesize host;
@synthesize sparkleBundle;

static NSMutableDictionary *sharedUpdaters = nil;
static NSString *const SUUpdaterDefaultsObservationContext = @"SUUpdaterDefaultsObservationContext";

+ (SUUpdater *)sharedUpdater
{
    return [self updaterForBundle:[NSBundle mainBundle]];
}

// SUUpdater has a singleton for each bundle. We use the fact that NSBundle instances are also singletons, so we can use them as keys. If you don't trust that you can also use the identifier as key
+ (SUUpdater *)updaterForBundle:(NSBundle *)bundle
{
    if (bundle == nil) bundle = [NSBundle mainBundle];
    id updater = sharedUpdaters[[NSValue valueWithNonretainedObject:bundle]];
    if (updater == nil) {
        updater = [[[self class] alloc] initForBundle:bundle];
    }
    return updater;
}

// This is the designated initializer for SUUpdater, important for subclasses
- (instancetype)initForBundle:(NSBundle *)bundle
{
    self = [super init];
    if (bundle == nil) bundle = [NSBundle mainBundle];

    // Use explicit class to use the correct bundle even when subclassed
    self.sparkleBundle = [NSBundle bundleForClass:[SUUpdater class]];
    if (!self.sparkleBundle) {
        SULog(@"Error: SUUpdater can't find Sparkle.framework it belongs to");
        return nil;
    }

    // Register as observer straight away to avoid exceptions on -dealloc when -unregisterAsObserver is called:
    if (self) {
        [self registerAsObserver];
    }

    id updater = sharedUpdaters[[NSValue valueWithNonretainedObject:bundle]];
    if (updater)
	{
        self = updater;
	}
	else if (self)
	{
        if (sharedUpdaters == nil) {
            sharedUpdaters = [[NSMutableDictionary alloc] init];
        }
        sharedUpdaters[[NSValue valueWithNonretainedObject:bundle]] = self;
        host = [[SUHost alloc] initWithBundle:bundle];

        // Saving-the-developer-from-a-stupid-mistake-check:
        // The check is async to give time to set a delegate, so that potentially-overriden feedURL works
        [self performSelector:@selector(checkIfConfiguredProperly) withObject:nil afterDelay:0];

        // This runs the permission prompt if needed, but never before the app has finished launching because the runloop won't run before that
        [self performSelector:@selector(startUpdateCycle) withObject:nil afterDelay:0];
    }
    return self;
}

-(void)showModalAlertText:(NSString *)text informativeText:(NSString *)informativeText {
    [self notifyWillShowModalAlert];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = text;
    alert.informativeText = informativeText;
    [alert runModal];
    [self notifyDidShowModalAlert];
}

-(void)checkIfConfiguredProperly {
    BOOL hasPublicDSAKey = [self.host publicDSAKey] != nil;
    BOOL isMainBundle = [self.host.bundle isEqualTo:[NSBundle mainBundle]];
    BOOL hostIsCodeSigned = [SUCodeSigningVerifier hostApplicationIsCodeSigned];
    NSURL *feedURL = [self feedURL];
    BOOL servingOverHttps = [[[feedURL scheme] lowercaseString] isEqualToString:@"https"];
    if (!isMainBundle && !hasPublicDSAKey) {
        [self showModalAlertText:@"Insecure update error!"
                 informativeText:@"For security reasons, you need to sign your updates with a DSA key. See Sparkle's documentation for more information."];
    } else if (isMainBundle && !(hasPublicDSAKey || hostIsCodeSigned)) {
        [self showModalAlertText:@"Insecure update error!"
                 informativeText:@"For security reasons, you need to code sign your application or sign your updates with a DSA key. See Sparkle's documentation for more information."];
    } else if (isMainBundle && !hasPublicDSAKey && !servingOverHttps) {
        SULog(@"WARNING: Serving updates over HTTP without signing them with a DSA key is deprecated and may not be possible in a future release. Please serve your updates over https, or sign them with a DSA key, or do both. See Sparkle's documentation for more information.");
    }

#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101100
    BOOL atsExceptionsExist = nil != [self.host objectForInfoDictionaryKey:@"NSAppTransportSecurity"];
    if (isMainBundle && !servingOverHttps && !atsExceptionsExist) {
        [self showModalAlertText:@"Insecure feed URL is blocked in OS X 10.11"
                 informativeText:[NSString stringWithFormat:@"You must change the feed URL (%@) to use HTTPS or disable App Transport Security.\n\nFor more information:\nhttp://sparkle-project.org/documentation/app-transport-security/", [feedURL absoluteString]]];
    }
    if (!isMainBundle && !servingOverHttps) {
        SULog(@"WARNING: Serving updates over HTTP may be blocked in OS X 10.11. Please change the feed URL (%@) to use HTTPS. For more information:\nhttp://sparkle-project.org/documentation/app-transport-security/", feedURL);
    }
#endif
}


// This will be used when the updater is instantiated in a nib such as MainMenu
- (instancetype)init
{
    return [self initForBundle:[NSBundle mainBundle]];
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@, %@>", [self class], [self.host bundlePath], [self.host installationPath]]; }


- (void)notifyWillShowModalAlert
{
    if ([self.delegate respondsToSelector:@selector(updaterWillShowModalAlert:)])
        [self.delegate updaterWillShowModalAlert:self];
}


- (void)notifyDidShowModalAlert
{
    if ([self.delegate respondsToSelector:@selector(updaterDidShowModalAlert:)])
        [self.delegate updaterDidShowModalAlert:self];
}


- (void)startUpdateCycle
{
    BOOL shouldPrompt = NO;
    BOOL hasLaunchedBefore = [self.host boolForUserDefaultsKey:SUHasLaunchedBeforeKey];

    // If the user has been asked about automatic checks, don't bother prompting
    if ([self.host objectForUserDefaultsKey:SUEnableAutomaticChecksKey]) {
        shouldPrompt = NO;
    }
    // Does the delegate want to take care of the logic for when we should ask permission to update?
    else if ([self.delegate respondsToSelector:@selector(updaterShouldPromptForPermissionToCheckForUpdates:)]) {
        shouldPrompt = [self.delegate updaterShouldPromptForPermissionToCheckForUpdates:self];
    }
    // Has he been asked already? And don't ask if the host has a default value set in its Info.plist.
    else if ([self.host objectForKey:SUEnableAutomaticChecksKey] == nil) {
        // Now, we don't want to ask the user for permission to do a weird thing on the first launch.
        // We wait until the second launch, unless explicitly overridden via SUPromptUserOnFirstLaunchKey.
        shouldPrompt = [self.host objectForKey:SUPromptUserOnFirstLaunchKey] || hasLaunchedBefore;
    }

    if (!hasLaunchedBefore) {
        [self.host setBool:YES forUserDefaultsKey:SUHasLaunchedBeforeKey];
    }

    if (shouldPrompt) {
        NSArray *profileInfo = [self.host systemProfile];
        // Always say we're sending the system profile here so that the delegate displays the parameters it would send.
        if ([self.delegate respondsToSelector:@selector(feedParametersForUpdater:sendingSystemProfile:)]) {
            profileInfo = [profileInfo arrayByAddingObjectsFromArray:[self.delegate feedParametersForUpdater:self sendingSystemProfile:YES]];
        }
        [SUUpdatePermissionPrompt promptWithHost:self.host systemProfile:profileInfo delegate:self];
        // We start the update checks and register as observer for changes after the prompt finishes
    } else {
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
	if ([note object] == self.driver && [self.driver finished])
	{
        self.driver = nil;
        [self scheduleNextUpdateCheck];
    }
}

- (NSDate *)lastUpdateCheckDate
{
    return [self.host objectForUserDefaultsKey:SULastCheckTimeKey];
}

- (void)scheduleNextUpdateCheck
{
	if (self.checkTimer)
	{
        [self.checkTimer invalidate];
        self.checkTimer = nil; // Timer is non-repeating, may have invalidated itself, so we had to retain it.
    }
	if (![self automaticallyChecksForUpdates]) return;

    // How long has it been since last we checked for an update?
    NSDate *lastCheckDate = [self lastUpdateCheckDate];
	if (!lastCheckDate) { lastCheckDate = [NSDate distantPast]; }
    NSTimeInterval intervalSinceCheck = [[NSDate date] timeIntervalSinceDate:lastCheckDate];

    // Now we want to figure out how long until we check again.
    NSTimeInterval delayUntilCheck, updateCheckInterval = [self updateCheckInterval];
    if (updateCheckInterval < SUMinimumUpdateCheckInterval)
        updateCheckInterval = SUMinimumUpdateCheckInterval;
    if (intervalSinceCheck < updateCheckInterval)
        delayUntilCheck = (updateCheckInterval - intervalSinceCheck); // It hasn't been long enough.
    else
        delayUntilCheck = 0; // We're overdue! Run one now.
    self.checkTimer = [NSTimer scheduledTimerWithTimeInterval:delayUntilCheck target:self selector:@selector(checkForUpdatesInBackground) userInfo:nil repeats:NO]; // Timer is non-repeating, may have invalidated itself, so we had to retain it.
}


- (void)putFeedURLIntoDictionary:(NSMutableDictionary *)theDict // You release this.
{
    theDict[@"feedURL"] = [self feedURL];
}

- (void)checkForUpdatesInBgReachabilityCheckWithDriver:(SUUpdateDriver *)inDriver /* RUNS ON ITS OWN THREAD */
{
    @try {
        // This method *must* be called on its own thread. SCNetworkReachabilityCheckByName
        //	can block, and it can be waiting a long time on slow networks, and we
        //	wouldn't want to beachball the main thread for a background operation.
        // We could use asynchronous reachability callbacks, but those aren't
        //	reliable enough and can 'get lost' sometimes, which we don't want.

		@autoreleasepool {
            SCNetworkConnectionFlags flags = 0;
            BOOL isNetworkReachable = YES;

            // Don't perform automatic checks on unconnected laptops or dial-up connections that aren't online:
            NSMutableDictionary *theDict = [NSMutableDictionary dictionary];
            dispatch_sync(dispatch_get_main_queue(), ^{
				[self putFeedURLIntoDictionary:theDict];	// Get feed URL on main thread, it's not safe to call elsewhere.
            });

            const char *hostname = [[(NSURL *)theDict[@"feedURL"] host] cStringUsingEncoding:NSUTF8StringEncoding];
            SCNetworkReachabilityRef reachability = SCNetworkReachabilityCreateWithName(NULL, hostname);
            Boolean reachabilityResult = NO;
            // If the feed's using a file:// URL, we won't be able to use reachability.
            if (reachability != NULL) {
                SCNetworkReachabilityGetFlags(reachability, &flags);
                CFRelease(reachability);
            }

			if( reachabilityResult )
			{
                BOOL reachable = (flags & kSCNetworkFlagsReachable) == kSCNetworkFlagsReachable;
                BOOL automatic = (flags & kSCNetworkFlagsConnectionAutomatic) == kSCNetworkFlagsConnectionAutomatic;
                BOOL local = (flags & kSCNetworkFlagsIsLocalAddress) == kSCNetworkFlagsIsLocalAddress;

                if (!(reachable || automatic || local))
                    isNetworkReachable = NO;
            }

            // If the network's not reachable, we pass a nil driver into checkForUpdatesWithDriver, which will then reschedule the next update so we try again later.
            dispatch_async(dispatch_get_main_queue(), ^{
				[self checkForUpdatesWithDriver: isNetworkReachable ? inDriver : nil];
            });

        }
	} @catch (NSException *localException) {
        SULog(@"UNCAUGHT EXCEPTION IN UPDATE CHECK TIMER: %@", [localException reason]);
        // Don't propagate the exception beyond here. In Carbon apps that would trash the stack.
    }
}


- (void)checkForUpdatesInBackground
{
    // Background update checks should only happen if we have a network connection.
    //	Wouldn't want to annoy users on dial-up by establishing a connection every
    //	hour or so:
    SUUpdateDriver *theUpdateDriver = [[([self automaticallyDownloadsUpdates] ? [SUAutomaticUpdateDriver class] : [SUScheduledUpdateDriver class])alloc] initWithUpdater:self];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		[self checkForUpdatesInBgReachabilityCheckWithDriver:theUpdateDriver];
    });
}


- (BOOL)mayUpdateAndRestart
{
    return (!self.delegate || ![self.delegate respondsToSelector:@selector(updaterShouldRelaunchApplication:)] || [self.delegate updaterShouldRelaunchApplication:self]);
}

- (IBAction)checkForUpdates:(id)__unused sender
{
    if (self.driver && [self.driver isInterruptible]) {
        [self.driver abortUpdate];
    }

    [self checkForUpdatesWithDriver:[[SUUserInitiatedUpdateDriver alloc] initWithUpdater:self]];
}

- (void)checkForUpdateInformation
{
    [self checkForUpdatesWithDriver:[[SUProbingUpdateDriver alloc] initWithUpdater:self]];
}

- (void)installUpdatesIfAvailable
{
    if (self.driver && [self.driver isInterruptible]) {
        [self.driver abortUpdate];
    }

    SUUIBasedUpdateDriver *theUpdateDriver = [[SUUserInitiatedUpdateDriver alloc] initWithUpdater:self];
    theUpdateDriver.automaticallyInstallUpdates = YES;
    [self checkForUpdatesWithDriver:theUpdateDriver];
}

- (void)checkForUpdatesWithDriver:(SUUpdateDriver *)d
{
	if ([self updateInProgress]) { return; }
	if (self.checkTimer) { [self.checkTimer invalidate]; self.checkTimer = nil; }		// Timer is non-repeating, may have invalidated itself, so we had to retain it.

    [self willChangeValueForKey:@"lastUpdateCheckDate"];
    [self.host setObject:[NSDate date] forUserDefaultsKey:SULastCheckTimeKey];
    [self didChangeValueForKey:@"lastUpdateCheckDate"];

    if( [self.delegate respondsToSelector: @selector(updaterMayCheckForUpdates:)] && ![self.delegate updaterMayCheckForUpdates: self] )
	{
        [self scheduleNextUpdateCheck];
        return;
    }

    self.driver = d;

    // If we're not given a driver at all, just schedule the next update check and bail.
    if (!self.driver)
    {
        [self scheduleNextUpdateCheck];
        return;
    }

    NSURL *theFeedURL = [self parameterizedFeedURL];
    if (theFeedURL) // Use a NIL URL to cancel quietly.
        [self.driver checkForUpdatesAtURL:theFeedURL host:self.host];
    else
        [self.driver abortUpdate];
}

- (void)registerAsObserver
{
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateDriverDidFinish:) name:SUUpdateDriverFinishedNotification object:nil];
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self forKeyPath:[@"values." stringByAppendingString:SUScheduledCheckIntervalKey] options:(NSKeyValueObservingOptions)0 context:(__bridge void *)(SUUpdaterDefaultsObservationContext)];
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self forKeyPath:[@"values." stringByAppendingString:SUEnableAutomaticChecksKey] options:(NSKeyValueObservingOptions)0 context:(__bridge void *)(SUUpdaterDefaultsObservationContext)];
}

- (void)unregisterAsObserver
{
	@try
	{
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        [[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self forKeyPath:[@"values." stringByAppendingString:SUScheduledCheckIntervalKey]];
        [[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self forKeyPath:[@"values." stringByAppendingString:SUEnableAutomaticChecksKey]];
    }
    @catch (NSException *)
    {
        SULog(@"Error: [SUUpdater unregisterAsObserver] called, but the updater wasn't registered as an observer.");
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (context == (__bridge void *)(SUUpdaterDefaultsObservationContext))
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
    [self.host setBool:automaticallyCheckForUpdates forUserDefaultsKey:SUEnableAutomaticChecksKey];
    // Hack to support backwards compatibility with older Sparkle versions, which supported
    // disabling updates by setting the check interval to 0.
    if (automaticallyCheckForUpdates && (NSInteger)[self updateCheckInterval] == 0) {
        [self setUpdateCheckInterval:SUDefaultUpdateCheckInterval];
    }
    [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(resetUpdateCycle) object:nil];
    // Provide a small delay in case multiple preferences are being updated simultaneously.
    [self performSelector:@selector(resetUpdateCycle) withObject:nil afterDelay:1];
}

- (BOOL)automaticallyChecksForUpdates
{
    // Don't automatically update when the check interval is 0, to be compatible with 1.1 settings.
    if ((NSInteger)[self updateCheckInterval] == 0) {
        return NO;
    }
    return [self.host boolForKey:SUEnableAutomaticChecksKey];
}

- (void)setAutomaticallyDownloadsUpdates:(BOOL)automaticallyUpdates
{
    [self.host setBool:automaticallyUpdates forUserDefaultsKey:SUAutomaticallyUpdateKey];
}

- (BOOL)automaticallyDownloadsUpdates
{
    // If the host doesn't allow automatic updates, don't ever let them happen
    if (!self.host.allowsAutomaticUpdates) {
        return NO;
    }

    // Otherwise, automatically downloading updates is allowed. Does the user want it?
    return [self.host boolForUserDefaultsKey:SUAutomaticallyUpdateKey];
}

- (void)setFeedURL:(NSURL *)feedURL
{
    if (![NSThread isMainThread])
        [NSException raise:@"SUThreadException" format:@"This method must be called on the main thread"];

    [self.host setObject:[feedURL absoluteString] forUserDefaultsKey:SUFeedURLKey];
}

- (NSURL *)feedURL
{
    if (![NSThread isMainThread])
        [NSException raise:@"SUThreadException" format:@"This method must be called on the main thread"];

    // A value in the user defaults overrides one in the Info.plist (so preferences panels can be created wherein users choose between beta / release feeds).
    NSString *appcastString = [self.host objectForKey:SUFeedURLKey];
    if ([self.delegate respondsToSelector:@selector(feedURLStringForUpdater:)])
        appcastString = [self.delegate feedURLStringForUpdater:self];
    if (!appcastString) // Can't find an appcast string!
        [NSException raise:@"SUNoFeedURL" format:@"You must specify the URL of the appcast as the %@ key in either the Info.plist or the user defaults!", SUFeedURLKey];
    NSCharacterSet *quoteSet = [NSCharacterSet characterSetWithCharactersInString:@"\"\'"]; // Some feed publishers add quotes; strip 'em.
    NSString *castUrlStr = [appcastString stringByTrimmingCharactersInSet:quoteSet];
    if (!castUrlStr || [castUrlStr length] == 0)
        return nil;
    else
        return [NSURL URLWithString:castUrlStr];
}

- (NSString *)userAgentString
{
    if (customUserAgentString) {
        return customUserAgentString;
    }

    NSString *version = [self.sparkleBundle objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey];
    NSString *userAgent = [NSString stringWithFormat:@"%@/%@ Sparkle/%@", [self.host name], [self.host displayVersion], version ? version : @"?"];
    NSData *cleanedAgent = [userAgent dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    return [[NSString alloc] initWithData:cleanedAgent encoding:NSASCIIStringEncoding];
}

- (void)setSendsSystemProfile:(BOOL)sendsSystemProfile
{
    [self.host setBool:sendsSystemProfile forUserDefaultsKey:SUSendProfileInfoKey];
}

- (BOOL)sendsSystemProfile
{
    return [self.host boolForKey:SUSendProfileInfoKey];
}

- (NSURL *)parameterizedFeedURL
{
    NSURL *baseFeedURL = [self feedURL];

    // Determine all the parameters we're attaching to the base feed URL.
    BOOL sendingSystemProfile = [self sendsSystemProfile];

    // Let's only send the system profiling information once per week at most, so we normalize daily-checkers vs. biweekly-checkers and the such.
    NSDate *lastSubmitDate = [self.host objectForUserDefaultsKey:SULastProfileSubmitDateKey];
    if (!lastSubmitDate) {
        lastSubmitDate = [NSDate distantPast];
    }
    const NSTimeInterval oneWeek = 60 * 60 * 24 * 7;
    sendingSystemProfile &= (-[lastSubmitDate timeIntervalSinceNow] >= oneWeek);

    NSArray *parameters = @[];
    if ([self.delegate respondsToSelector:@selector(feedParametersForUpdater:sendingSystemProfile:)]) {
        parameters = [parameters arrayByAddingObjectsFromArray:[self.delegate feedParametersForUpdater:self sendingSystemProfile:sendingSystemProfile]];
    }
	if (sendingSystemProfile)
	{
        parameters = [parameters arrayByAddingObjectsFromArray:[self.host systemProfile]];
        [self.host setObject:[NSDate date] forUserDefaultsKey:SULastProfileSubmitDateKey];
    }
	if ([parameters count] == 0) { return baseFeedURL; }

    // Build up the parameterized URL.
    NSMutableArray *parameterStrings = [NSMutableArray array];
    for (NSDictionary *currentProfileInfo in parameters) {
        [parameterStrings addObject:[NSString stringWithFormat:@"%@=%@", [[currentProfileInfo[@"key"] description] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding], [[currentProfileInfo[@"value"] description] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
    }

    NSString *separatorCharacter = @"?";
    if ([baseFeedURL query]) {
        separatorCharacter = @"&"; // In case the URL is already http://foo.org/baz.xml?bat=4
    }
    NSString *appcastStringWithProfile = [NSString stringWithFormat:@"%@%@%@", [baseFeedURL absoluteString], separatorCharacter, [parameterStrings componentsJoinedByString:@"&"]];

    // Clean it up so it's a valid URL
    return [NSURL URLWithString:appcastStringWithProfile];
}

- (void)setUpdateCheckInterval:(NSTimeInterval)updateCheckInterval
{
    [self.host setObject:@(updateCheckInterval) forUserDefaultsKey:SUScheduledCheckIntervalKey];
    if ((NSInteger)updateCheckInterval == 0) { // For compatibility with 1.1's settings.
        [self setAutomaticallyChecksForUpdates:NO];
    }
    [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(resetUpdateCycle) object:nil];

    // Provide a small delay in case multiple preferences are being updated simultaneously.
    [self performSelector:@selector(resetUpdateCycle) withObject:nil afterDelay:1];
}

- (NSTimeInterval)updateCheckInterval
{
    // Find the stored check interval. User defaults override Info.plist.
    NSNumber *intervalValue = [self.host objectForKey:SUScheduledCheckIntervalKey];
    if (intervalValue)
        return [intervalValue doubleValue];
    else
        return SUDefaultUpdateCheckInterval;
}

- (void)dealloc
{
    [self unregisterAsObserver];
	if (checkTimer) { [checkTimer invalidate]; }		// Timer is non-repeating, may have invalidated itself, so we had to retain it.
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(checkForUpdates:)) {
        return ![self updateInProgress];
    }
    return YES;
}

- (BOOL)updateInProgress
{
    return self.driver && ([self.driver finished] == NO);
}

- (NSBundle *)hostBundle { return [self.host bundle]; }

@end
