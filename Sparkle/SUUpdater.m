//
//  SUUpdater.m
//  Sparkle
//
//  Created by Andy Matuschak on 1/4/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUUpdater.h"
#import "SUUpdaterDelegate.h"
#import "SUHost.h"
#import "SUUpdatePermissionPromptResult.h"
#import "SUUpdateDriver.h"
#import "SUConstants.h"
#import "SULog.h"
#import "SUCodeSigningVerifier.h"
#import "SUSystemProfiler.h"
#include <SystemConfiguration/SystemConfiguration.h>
#import "SUScheduledUpdateDriver.h"
#import "SUProbingUpdateDriver.h"
#import "SUUserInitiatedUpdateDriver.h"
#import "SUAutomaticUpdateDriver.h"
#import "SURemoteMessagePort.h"
#import "SUMessageTypes.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

NSString *const SUUpdaterDidFinishLoadingAppCastNotification = @"SUUpdaterDidFinishLoadingAppCastNotification";
NSString *const SUUpdaterDidFindValidUpdateNotification = @"SUUpdaterDidFindValidUpdateNotification";
NSString *const SUUpdaterDidNotFindUpdateNotification = @"SUUpdaterDidNotFindUpdateNotification";
NSString *const SUUpdaterWillRestartNotification = @"SUUpdaterWillRestartNotificationName";
NSString *const SUUpdaterAppcastItemNotificationKey = @"SUUpdaterAppcastItemNotificationKey";
NSString *const SUUpdaterAppcastNotificationKey = @"SUUpdaterAppCastNotificationKey";

@interface SUUpdater ()

@property (strong) NSBundle *sparkleBundle;
@property (readonly, copy) NSURL *parameterizedFeedURL;

@property (strong) id <SUUpdateDriver> driver;
@property (strong) SUHost *host;

@end

@implementation SUUpdater

@synthesize delegate;
@synthesize userDriver = _userDriver;
@synthesize userAgentString = customUserAgentString;
@synthesize httpHeaders;
@synthesize driver;
@synthesize host;
@synthesize sparkleBundle;
@synthesize decryptionPassword;

- (instancetype)initWithHostBundle:(NSBundle *)bundle userDriver:(id <SUUserDriver>)userDriver delegate:(id <SUUpdaterDelegate>)theDelegate
{
    self = [super init];
    
    if (self != nil) {
        // Use explicit class to use the correct bundle even when subclassed
        self.sparkleBundle = [NSBundle bundleForClass:[SUUpdater class]];
        if (!self.sparkleBundle) {
            SULog(@"Error: SUUpdater can't find Sparkle.framework it belongs to");
            return nil;
        }
        
        host = [[SUHost alloc] initWithBundle:bundle];
        
        _userDriver = userDriver;
        
        delegate = theDelegate;
        
        // This runs the permission prompt if needed, but never before the app has finished launching because the runloop may not have ran before that
        // We will also take precaussions if a developer instantiates an updater themselves where the application may not be completely finished launching yet
        [self performSelector:@selector(startUpdateCycle) withObject:nil afterDelay:1];
    }
    
    return self;
}

// To prevent subclasses from doing something bad based on older Sparkle code
- (instancetype)initForBundle:(NSBundle *)__unused bundle
{
    [NSException raise:@"SUUpdaterInitForBundleNotImplemented" format:@"-[SUUpdater initForBundle:] is not implemented anymore."];
    return nil;
}

// To prevent trying to stick an SUUpdater in a nib or initializing it in an incorrect way
- (instancetype)init
{
    [NSException raise:@"SUUpdaterInitNotImplemented" format:@"-[SUUpdater init] is not implemented. If you want to drop an updater into a nib, see SUUpdaterController"];
    return nil;
}

-(void)checkIfConfiguredProperly {
    BOOL hasPublicDSAKey = [self.host publicDSAKey] != nil;
    BOOL isMainBundle = [self.host.bundle isEqualTo:[NSBundle mainBundle]];
    BOOL hostIsCodeSigned = [SUCodeSigningVerifier applicationAtPathIsCodeSigned:self.host.bundle.bundlePath];
    NSURL *feedURL = [self feedURL];
    BOOL servingOverHttps = [[[feedURL scheme] lowercaseString] isEqualToString:@"https"];
    if (!isMainBundle && !hasPublicDSAKey) {
        [NSException raise:@"SUNoPublicDSAFound" format:@"For security reasons, you need to sign your updates with a DSA key. See Sparkle's documentation for more information."];
    } else if (isMainBundle && !(hasPublicDSAKey || hostIsCodeSigned)) {
        [NSException raise:@"SUInsufficientSigning" format:@"For security reasons, you need to code sign your application or sign your updates with a DSA key. See Sparkle's documentation for more information."];
    } else if (isMainBundle && !hasPublicDSAKey && !servingOverHttps) {
        SULog(@"WARNING: Serving updates over HTTP without signing them with a DSA key is deprecated and may not be possible in a future release. Please serve your updates over https, or sign them with a DSA key, or do both. See Sparkle's documentation for more information.");
    }

#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101100
    BOOL atsExceptionsExist = nil != [self.host objectForInfoDictionaryKey:@"NSAppTransportSecurity"];
    if (isMainBundle && !servingOverHttps && !atsExceptionsExist) {
        [NSException raise:@"SUInsecureFeedURL" format:@"You must change the feed URL (%@) to use HTTPS or disable App Transport Security.\n\nFor more information:\nhttp://sparkle-project.org/documentation/app-transport-security/", [feedURL absoluteString]];
    }
    if (!isMainBundle && !servingOverHttps) {
        SULog(@"WARNING: Serving updates over HTTP may be blocked in OS X 10.11. Please change the feed URL (%@) to use HTTPS. For more information:\nhttp://sparkle-project.org/documentation/app-transport-security/", feedURL);
    }
#endif
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@, %@>", [self class], [self.host bundlePath], [self.host installationPath]]; }

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
        NSArray *profileInfo = [SUSystemProfiler systemProfileArrayForHost:self.host];
        // Always say we're sending the system profile here so that the delegate displays the parameters it would send.
        if ([self.delegate respondsToSelector:@selector(feedParametersForUpdater:sendingSystemProfile:)]) {
            NSArray *feedParameters = [self.delegate feedParametersForUpdater:self sendingSystemProfile:YES];
            if (feedParameters != nil) {
                profileInfo = [profileInfo arrayByAddingObjectsFromArray:feedParameters];
            }
        }
        
        [self.userDriver requestUpdatePermissionWithSystemProfile:profileInfo reply:^(SUUpdatePermissionPromptResult *result) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updatePermissionPromptFinishedWithResult:result];
            });
        }];
        
        // We start the update checks and register as observer for changes after the prompt finishes
    } else {
        // We check if the user's said they want updates, or they haven't said anything, and the default is set to checking.
        [self scheduleNextUpdateCheck];
    }
}

- (void)updatePermissionPromptFinishedWithResult:(SUUpdatePermissionPromptResult *)result
{
    [self.host setBool:result.shouldSendProfile forUserDefaultsKey:SUSendProfileInfoKey];
    [self setAutomaticallyChecksForUpdates:(result.choice == SUAutomaticallyCheck)];
    // Schedule checks, but make sure we ignore the delayed call from KVO
    [self resetUpdateCycle];
}

- (NSDate *)lastUpdateCheckDate
{
    return [self.host objectForUserDefaultsKey:SULastCheckTimeKey];
}

- (void)updateLastUpdateCheckDate
{
    [self willChangeValueForKey:NSStringFromSelector(@selector(lastUpdateCheckDate))];
    [self.host setObject:[NSDate date] forUserDefaultsKey:SULastCheckTimeKey];
    [self didChangeValueForKey:NSStringFromSelector(@selector(lastUpdateCheckDate))];
}

- (void)scheduleNextUpdateCheck
{
    [self.userDriver invalidateUpdateCheckTimer];
    
    if (![self automaticallyChecksForUpdates]) {
        [self.userDriver idleOnUpdateChecks:YES];
        return;
    } else {
        [self.userDriver idleOnUpdateChecks:NO];
    }

    // How long has it been since last we checked for an update?
    NSDate *lastCheckDate = [self lastUpdateCheckDate];
	if (!lastCheckDate) { lastCheckDate = [NSDate distantPast]; }
    NSTimeInterval intervalSinceCheck = [[NSDate date] timeIntervalSinceDate:lastCheckDate];

    // Now we want to figure out how long until we check again.
    NSTimeInterval updateCheckInterval = [self updateCheckInterval];
    if (updateCheckInterval < SUMinimumUpdateCheckInterval)
        updateCheckInterval = SUMinimumUpdateCheckInterval;
    if (intervalSinceCheck < updateCheckInterval) {
        NSTimeInterval delayUntilCheck = (updateCheckInterval - intervalSinceCheck); // It hasn't been long enough.
        [self.userDriver startUpdateCheckTimerWithNextTimeInterval:delayUntilCheck reply:^(SUUpdateCheckTimerStatus checkTimerStatus) {
            switch (checkTimerStatus) {
                case SUCheckForUpdateWillOccurLater:
                    break;
                case SUCheckForUpdateNow:
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self checkForUpdatesInBackground];
                    });
                    break;
            }
        }];
    } else {
        // We're overdue! Run one now.
        [self checkForUpdatesInBackground];
    }
}

// RUNS ON ITS OWN THREAD
// updater should be passed as a weak reference
static void SUCheckForUpdatesInBgReachabilityCheck(__weak SUUpdater *updater, id <SUUpdateDriver> inDriver)
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
                // Get feed URL on main thread, it's not safe to call elsewhere.
                theDict[@"feedURL"] = [updater feedURL];;
            });
            
            // Did the updater get deallocated already?
            if (theDict.count == 0 || updater == nil) {
                return;
            }
            
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
                // Is the updater still alive?
                if (updater != nil) {
                    [updater checkForUpdatesWithDriver: isNetworkReachable ? inDriver : nil];
                }
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
    
    id <SUUpdateDriver> updateDriver;
    if ([self automaticallyDownloadsUpdates]) {
        updateDriver =
        [[SUAutomaticUpdateDriver alloc]
         initWithHost:self.host
         sparkleBundle:self.sparkleBundle
         updater:self
         updaterDelegate:self.delegate];
    } else {
        updateDriver =
        [[SUScheduledUpdateDriver alloc]
         initWithHost:self.host
         sparkleBundle:self.sparkleBundle
         updater:self
         userDriver:self.userDriver
         updaterDelegate:self.delegate];
    }
    
    // We don't want the reachability check to act on the driver if the updater is going near death
    __weak SUUpdater *updater = self;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SUCheckForUpdatesInBgReachabilityCheck(updater, updateDriver);
    });
}

- (void)checkForUpdates
{
    if (self.driver != nil) {
        [self.driver abortUpdate];
    }
    
//    if (self.driver && [self.driver isInterruptible]) {
//        [self.driver abortUpdate];
//    }
    
    id <SUUpdateDriver> theUpdateDriver = [[SUUserInitiatedUpdateDriver alloc] initWithHost:self.host sparkleBundle:self.sparkleBundle updater:self userDriver:self.userDriver updaterDelegate:self.delegate];
    [self checkForUpdatesWithDriver:theUpdateDriver];
}

- (void)checkForUpdateInformation
{
    [self checkForUpdatesWithDriver:[[SUProbingUpdateDriver alloc] initWithHost:self.host updater:self updaterDelegate:self.delegate]];
}

- (void)checkForUpdatesWithDriver:(id <SUUpdateDriver> )d
{
    if ([self updateInProgress]) {
        return;
    }
    
    [self.userDriver invalidateUpdateCheckTimer];

    [self updateLastUpdateCheckDate];

    if( [self.delegate respondsToSelector: @selector(updaterMayCheckForUpdates:)] && ![self.delegate updaterMayCheckForUpdates: self] )
	{
        [self scheduleNextUpdateCheck];
        return;
    }

    self.driver = d;
    
    // If we're not given a driver at all, just schedule the next update check and bail.
    if (!self.driver) {
        [self scheduleNextUpdateCheck];
        return;
    }
    
    [self.userDriver showUpdateInProgress:YES];

    [self checkIfConfiguredProperly];

    NSURL *theFeedURL = [self parameterizedFeedURL];
    // Use a NIL URL to cancel quietly.
    if (theFeedURL) {
        [self.driver checkForUpdatesAtAppcastURL:theFeedURL withUserAgent:[self userAgentString] httpHeaders:[self httpHeaders] completion:^{
            self.driver = nil;
            [self.userDriver showUpdateInProgress:NO];
            [self updateLastUpdateCheckDate];
            [self scheduleNextUpdateCheck];
        }];
    } else {
        [self.driver abortUpdate];
    }
}

- (void)cancelNextUpdateCycle
{
    [[self class] cancelPreviousPerformRequestsWithTarget:self selector:@selector(resetUpdateCycle) object:nil];
}

- (void)resetUpdateCycle
{
    [self cancelNextUpdateCycle];
    [self scheduleNextUpdateCheck];
}

- (void)resetUpdateCycleAfterShortDelay
{
    [self cancelNextUpdateCycle];
    [self performSelector:@selector(resetUpdateCycle) withObject:nil afterDelay:1];
}

- (void)setAutomaticallyChecksForUpdates:(BOOL)automaticallyCheckForUpdates
{
    [self.host setBool:automaticallyCheckForUpdates forUserDefaultsKey:SUEnableAutomaticChecksKey];
    // Hack to support backwards compatibility with older Sparkle versions, which supported
    // disabling updates by setting the check interval to 0.
    if (automaticallyCheckForUpdates && (NSInteger)[self updateCheckInterval] == 0) {
        [self setUpdateCheckInterval:SUDefaultUpdateCheckInterval];
    }
    [self cancelNextUpdateCycle];
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
    
    // Can we automatically update in the background without bugging the user (e.g, with a administrator password prompt)?
    if (![[NSFileManager defaultManager] isWritableFileAtPath:self.host.bundlePath]) {
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
        NSArray *feedParameters = [self.delegate feedParametersForUpdater:self sendingSystemProfile:sendingSystemProfile];
        if (feedParameters != nil) {
            parameters = [parameters arrayByAddingObjectsFromArray:feedParameters];
        }
    }
	if (sendingSystemProfile)
	{
        parameters = [parameters arrayByAddingObjectsFromArray:[SUSystemProfiler systemProfileArrayForHost:self.host]];
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
    [self cancelNextUpdateCycle];

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
    // Remove updater did finish notification
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Stop checking for updates
    [self cancelNextUpdateCycle];
    
    // Don't tell the user driver to invalidate the update check timer
    // It could always create a new updater instance once the scheduled time occurs
    
    // Abort any on-going updates
    // A driver could be retained by another object (eg: a timer),
    // so not aborting could mean it stays alive longer than we'd want
    [self.driver abortUpdate];
    self.driver = nil;
}

- (BOOL)updateInProgress
{
    if (self.driver != nil) {
        return YES;
    }
    
    SURemoteMessagePort *remotePort = [[SURemoteMessagePort alloc] initWithServiceName:SUAutoUpdateServiceNameForHost(self.host) invalidationCallback:^{}];
    BOOL installerAlive = (remotePort != nil);
    [remotePort invalidate];
    
    if (installerAlive) {
        return YES;
    }
    
    return NO;
}

- (NSBundle *)hostBundle { return [self.host bundle]; }

@end
