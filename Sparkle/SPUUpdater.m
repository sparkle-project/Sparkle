//
//  SPUUpdater.m
//  Sparkle
//
//  Created by Andy Matuschak on 1/4/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SPUUpdater.h"
#import "SUUpdaterDelegate.h"
#import "SPUUpdaterSettings.h"
#import "SUHost.h"
#import "SPUUpdatePermission.h"
#import "SUUpdateDriver.h"
#import "SUConstants.h"
#import "SULog.h"
#import "SUCodeSigningVerifier.h"
#import "SUSystemProfiler.h"
#import "SUScheduledUpdateDriver.h"
#import "SUProbingUpdateDriver.h"
#import "SUUserInitiatedUpdateDriver.h"
#import "SUAutomaticUpdateDriver.h"
#import "SUProbeInstallStatus.h"
#import "SUAppcastItem.h"
#import "SPUInstallationInfo.h"
#import "SUErrors.h"
#import "SPUXPCServiceInfo.h"
#import "SPUUpdaterCycle.h"
#import "SUDownloadedUpdate.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

NSString *const SUUpdaterDidFinishLoadingAppCastNotification = @"SUUpdaterDidFinishLoadingAppCastNotification";
NSString *const SUUpdaterDidFindValidUpdateNotification = @"SUUpdaterDidFindValidUpdateNotification";
NSString *const SUUpdaterDidNotFindUpdateNotification = @"SUUpdaterDidNotFindUpdateNotification";
NSString *const SUUpdaterWillRestartNotification = @"SUUpdaterWillRestartNotificationName";
NSString *const SUUpdaterAppcastItemNotificationKey = @"SUUpdaterAppcastItemNotificationKey";
NSString *const SUUpdaterAppcastNotificationKey = @"SUUpdaterAppCastNotificationKey";

@interface SPUUpdater () <SPUUpdaterCycleDelegate>

@property (readonly, copy) NSURL *parameterizedFeedURL;

@property (nonatomic) id <SUUpdateDriver> driver;
@property (nonatomic, weak) id delegator;
@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, readonly) SPUUpdaterSettings *updaterSettings;
@property (nonatomic, readonly) SPUUpdaterCycle *updaterCycle;
@property (nonatomic) BOOL startedUpdater;
@property (nonatomic, copy) void (^preStartedScheduledUpdateBlock)(void);
@property (nonatomic, nullable) SUDownloadedUpdate *resumableUpdate;

@property (nonatomic) BOOL loggedATSWarning;
@property (nonatomic) BOOL loggedDSAWarning;

@end

@implementation SPUUpdater

@synthesize delegate = _delegate;
@synthesize delegator = _delegator;
@synthesize userDriver = _userDriver;
@synthesize userAgentString = customUserAgentString;
@synthesize httpHeaders;
@synthesize driver;
@synthesize host = _host;
@synthesize updaterSettings = _updaterSettings;
@synthesize updaterCycle = _updaterCycle;
@synthesize sparkleBundle = _sparkleBundle;
@synthesize startedUpdater = _startedUpdater;
@synthesize preStartedScheduledUpdateBlock = _preStartedScheduledUpdateBlock;
@synthesize resumableUpdate = _resumableUpdate;
@synthesize loggedATSWarning = _loggedATSWarning;
@synthesize loggedDSAWarning = _loggedDSAWarning;

#ifdef DEBUG
+ (void)load
{
    // We're using NSLog instead of SULog here because we don't want to start Sparkle's logger here,
    // and because this is not really an error, just a warning notice
    NSLog(@"WARNING: This is running a Debug build of Sparkle; don't use this in production!");
}
#endif

- (instancetype)initWithHostBundle:(NSBundle *)bundle userDriver:(id <SPUUserDriver>)userDriver delegate:(id <SUUpdaterDelegate>)theDelegate
{
    self = [super init];
    
    if (self != nil) {
        // Use explicit class to use the correct bundle even when subclassed
        _sparkleBundle = [NSBundle bundleForClass:[SPUUpdater class]];
        
        _host = [[SUHost alloc] initWithBundle:bundle];
        
        _updaterSettings = [[SPUUpdaterSettings alloc] initWithHostBundle:bundle];
        _updaterCycle = [[SPUUpdaterCycle alloc] initWithDelegate:self];
        
        _userDriver = userDriver;
        
        _delegate = theDelegate;
        
        // This property can be changed by an SUUpdater instance using us to setting our delegator to itself
        // This is why the updater types in the SUUpdaterDelegate are 'id' - because they can be SPUUpdater or SUUpdater
        // This is not a really a big deal because using the sender type is normally bad practice, and us passing it was a regretful decision in the first place.
        _delegator = self;
    }
    
    return self;
}

// To prevent subclasses from doing something bad based on older Sparkle code
- (instancetype)initForBundle:(NSBundle *)__unused bundle
{
    SULog(@"-[%@ initForBundle:] is not implemented anymore.", NSStringFromClass([self class]));
    abort();
    return nil;
}

// To prevent trying to stick an SUUpdater in a nib or initializing it in an incorrect way
- (instancetype)init
{
    SULog(@"-[%@ init] is not implemented. If you want to drop an updater into a nib, see SUStandardUpdaterController.", NSStringFromClass([self class]));
    abort();
    return nil;
}

- (BOOL)startUpdater:(NSError * __autoreleasing *)error
{
    if (![self checkIfConfiguredProperly:error]) {
        return NO;
    }
    
    self.startedUpdater = YES;
    [self startUpdateCycle];
    return YES;
}

- (BOOL)checkATSIssueForBundle:(NSBundle * _Nullable)bundle getBundleExists:(BOOL *)bundleExists
{
    if (bundleExists != NULL) {
        *bundleExists = (bundle != nil);
    }
    
    if (bundle == nil) {
        return NO;
    }
    
    return ([bundle objectForInfoDictionaryKey:@"NSAppTransportSecurity"] == nil);
}

- (BOOL)checkIfConfiguredProperly:(NSError * __autoreleasing *)error
{
    if (self.sparkleBundle == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInvalidUpdaterError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ can't find Sparkle.framework it belongs to.", NSStringFromClass([self class])] }];
        }
        return NO;
    }
    
    NSURL *feedURL = nil;
    if (![self retrieveFeedURL:&feedURL error:error]) {
        return NO;
    }
    
    if ([[self hostBundle] bundleIdentifier] == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInvalidHostBundleIdentifierError userInfo:@{ NSLocalizedDescriptionKey: @"Sparkle cannot target a bundle that does not have a valid bundle identifier." }];
        }
        return NO;
    }
    
    if (!self.host.validVersion) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInvalidHostVersionError userInfo:@{ NSLocalizedDescriptionKey: @"Sparkle cannot target a bundle that does not have a valid version." }];
        }
        return NO;
    }
    
    BOOL servingOverHttps = [[[feedURL scheme] lowercaseString] isEqualToString:@"https"];
    if (!servingOverHttps) {
        BOOL foundXPCTemporaryDownloaderService = NO;
        BOOL foundATSTemporaryIssue = [self checkATSIssueForBundle:SPUXPCServiceBundle(@TEMPORARY_DOWNLOADER_BUNDLE_ID) getBundleExists:&foundXPCTemporaryDownloaderService];
        
        BOOL foundXPCPersistentDownloaderService = NO;
        BOOL foundATSPersistentIssue = NO;
        if (!foundATSTemporaryIssue) {
            foundATSPersistentIssue = [self checkATSIssueForBundle:SPUXPCServiceBundle(@PERSISTENT_DOWNLOADER_BUNDLE_ID) getBundleExists:&foundXPCPersistentDownloaderService];
        }
        
        NSBundle *mainBundle = [NSBundle mainBundle];
        BOOL foundATSMainBundleIssue = NO;
        if (!foundATSTemporaryIssue && !foundATSPersistentIssue && (!foundXPCTemporaryDownloaderService || !foundXPCPersistentDownloaderService)) {
            BOOL foundATSIssue = ([mainBundle objectForInfoDictionaryKey:@"NSAppTransportSecurity"] == nil);
            BOOL updatingMainBundle = [self.host.bundle isEqualTo:mainBundle];
            
            if (updatingMainBundle) {
                // The only way we'll know for sure if there is an issue is if the main bundle is the same as the one we're updating
                // We don't want to generate false positives..
                foundATSMainBundleIssue = foundATSIssue;
            }
        }
        
        if (foundATSTemporaryIssue || foundATSPersistentIssue || foundATSMainBundleIssue) {
            if (!self.loggedATSWarning) {
                // Just log a warning. Don't outright fail in case we are wrong (eg: app is linked on an old SDK where ATS doesn't take effect)
                SULog(@"The feed URL (%@) may need to change to use HTTPS.\nFor more information: https://sparkle-project.org/documentation/app-transport-security", [feedURL absoluteString]);
                
                self.loggedATSWarning = YES;
            }
        }
    }
    
    BOOL hasPublicDSAKey = [self.host publicDSAKey] != nil;
    if (!hasPublicDSAKey) {
        // If we failed to retrieve a DSA key but the bundle specifies a path to one, we should consider this a configuration failure
        NSString *publicDSAKeyFileKey = [self.host publicDSAKeyFileKey];
        if (publicDSAKeyFileKey != nil) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUNoPublicDSAFoundError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The DSA public key '%@' could not be found.", publicDSAKeyFileKey] }];
            }
            return NO;
        }
    }
    
    if (!hasPublicDSAKey) {
        if (!servingOverHttps) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUNoPublicDSAFoundError userInfo:@{ NSLocalizedDescriptionKey: @"For security reasons, updates need to be signed with a DSA key. See Sparkle's documentation for more information." }];
            }
            return NO;
        } else {
            if (!self.loggedDSAWarning) {
                // Deprecated because we pass the downloaded archive to the installer and the installer has no way of knowing where the download came from.
                // Even if it did, the server and the download on it could still be compromised. But if a DSA signature was used, the private key should
                // not be stored on the server serving the update
                SULog(@"DEPRECATION: Serving updates without a DSA key is now deprecated and may be removed from a future release. See Sparkle's documentation for more information.");
                
                self.loggedDSAWarning = YES;
            }
        }
    }
    
    return YES;
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], [self.host bundlePath]]; }

- (void)startUpdateCycle
{
    BOOL shouldPrompt = NO;
    NSNumber *timeIntervalAtFirstLaunch = [self.host objectForUserDefaultsKey:SUTimeIntervalAtFirstLaunchKey];
    NSDate *currentDate = [NSDate date];

    // If the user has been asked about automatic checks, don't bother prompting
    if ([self.host objectForUserDefaultsKey:SUEnableAutomaticChecksKey]) {
        shouldPrompt = NO;
    }
    // If the developer wants to check for updates, we shouldn't bug the user about a prompt yet
    else if (self.preStartedScheduledUpdateBlock != nil) {
        shouldPrompt = NO;
    }
    // Does the delegate want to take care of the logic for when we should ask permission to update?
    else if ([self.delegate respondsToSelector:@selector(updaterShouldPromptForPermissionToCheckForUpdates:)]) {
        shouldPrompt = [self.delegate updaterShouldPromptForPermissionToCheckForUpdates:self.delegator];
    }
    // Has the user been asked already? And don't ask if the host has a default value set in its Info.plist.
    else if ([self.host objectForKey:SUEnableAutomaticChecksKey] == nil) {
        // Now, we don't want to ask the user for permission to do a weird thing right when they install the app
        // We wait until another launch after a few hours have passed, unless explicitly overridden via SUPromptUserOnFirstLaunchKey.
        
        if ([self.host objectForKey:SUPromptUserOnFirstLaunchKey] != nil) {
            shouldPrompt = YES;
        } else if (timeIntervalAtFirstLaunch != nil) {
            NSDate *firstLaunchDate = [NSDate dateWithTimeIntervalSinceReferenceDate:timeIntervalAtFirstLaunch.doubleValue];
            NSTimeInterval intervalSinceFirstLaunch = [currentDate timeIntervalSinceDate:firstLaunchDate];
            // We want to prompt if more than (or equal to) 'SUDefaultUpdatePermissionPromptInterval' seconds have passed since the first launch
            // If the first launch time is after (or equal to) our current date, then something may have gone wrong in the system - prompt to be on the safe side
            if (intervalSinceFirstLaunch >= SUDefaultUpdatePermissionPromptInterval || intervalSinceFirstLaunch <= 0) {
                shouldPrompt = YES;
            }
        }
    }
    
    if (timeIntervalAtFirstLaunch == nil) {
        [self.host setObject:@([currentDate timeIntervalSinceReferenceDate]) forUserDefaultsKey:SUTimeIntervalAtFirstLaunchKey];
    }

    if (shouldPrompt) {
        NSArray *profileInfo = [SUSystemProfiler systemProfileArrayForHost:self.host];
        // Always say we're sending the system profile here so that the delegate displays the parameters it would send.
        if ([self.delegate respondsToSelector:@selector(feedParametersForUpdater:sendingSystemProfile:)]) {
            NSArray *feedParameters = [self.delegate feedParametersForUpdater:self.delegator sendingSystemProfile:YES];
            if (feedParameters != nil) {
                profileInfo = [profileInfo arrayByAddingObjectsFromArray:feedParameters];
            }
        }
        
        __weak SPUUpdater *weakSelf = self;
        [self.userDriver requestUpdatePermissionWithSystemProfile:profileInfo reply:^(SPUUpdatePermission *result) {
            dispatch_async(dispatch_get_main_queue(), ^{
                SPUUpdater *strongSelf = weakSelf;
                if (strongSelf != nil) {
                    [strongSelf updatePermissionPromptFinishedWithResult:result];
                    // Schedule checks, but make sure we ignore the delayed call from KVO
                    [strongSelf resetUpdateCycle];
                }
            });
        }];
        
        // We start the update checks and register as observer for changes after the prompt finishes
    } else {
        if (self.preStartedScheduledUpdateBlock != nil) {
            self.preStartedScheduledUpdateBlock();
            self.preStartedScheduledUpdateBlock = nil;
        } else {
            // We check if the user's said they want updates, or they haven't said anything, and the default is set to checking.
            [self scheduleNextUpdateCheck];
        }
    }
}

- (void)updatePermissionPromptFinishedWithResult:(SPUUpdatePermission *)result
{
    [self.host setBool:result.sendProfile forUserDefaultsKey:SUSendProfileInfoKey];
    [self setAutomaticallyChecksForUpdates:(result.choice == SUAutomaticallyCheck)];
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
    [self scheduleNextUpdateCheckFiringImmediately:NO];
}

- (void)scheduleNextUpdateCheckFiringImmediately:(BOOL)firingImmediately
{
    [self.userDriver invalidateUpdateCheckTimer];
    
    BOOL automaticallyCheckForUpdates = [self automaticallyChecksForUpdates];
    
    [self.userDriver showCanCheckForUpdates:!automaticallyCheckForUpdates];
    [self.userDriver idleOnUpdateChecks:!automaticallyCheckForUpdates];
    
    if (!automaticallyCheckForUpdates) {
        return;
    }
    
    if (firingImmediately) {
        [self checkForUpdatesInBackground];
    } else {
        [self.userDriver showCanCheckForUpdates:YES];
        
        [self retrieveNextUpdateCheckInterval:^(NSTimeInterval updateCheckInterval) {
            // How long has it been since last we checked for an update?
            NSDate *lastCheckDate = [self lastUpdateCheckDate];
            if (!lastCheckDate) { lastCheckDate = [NSDate distantPast]; }
            NSTimeInterval intervalSinceCheck = [[NSDate date] timeIntervalSinceDate:lastCheckDate];
            
            // Now we want to figure out how long until we check again.
            if (updateCheckInterval < SUMinimumUpdateCheckInterval)
                updateCheckInterval = SUMinimumUpdateCheckInterval;
            if (intervalSinceCheck < updateCheckInterval) {
                NSTimeInterval delayUntilCheck = (updateCheckInterval - intervalSinceCheck); // It hasn't been long enough.
                __weak SPUUpdater *weakSelf = self; // we don't want this to keep the updater alive
                [self.userDriver startUpdateCheckTimerWithNextTimeInterval:delayUntilCheck reply:^(SUUpdateCheckTimerStatus checkTimerStatus) {
                    switch (checkTimerStatus) {
                        case SUCheckForUpdateWillOccurLater:
                            break;
                        case SUCheckForUpdateNow:
                            dispatch_async(dispatch_get_main_queue(), ^{
                                [weakSelf checkForUpdatesInBackground];
                            });
                            break;
                    }
                }];
            } else {
                // We're overdue! Run one now.
                [self checkForUpdatesInBackground];
            }
        }];
    }
}

- (void)checkForUpdatesInBackground
{
    if (!self.startedUpdater) {
        __weak SPUUpdater *weakSelf = self;
        self.preStartedScheduledUpdateBlock = ^{
            [weakSelf checkForUpdatesInBackground];
        };
        return;
    }
    
    // We don't want the probe check to act on the driver if the updater is going near death
    __weak SPUUpdater *weakSelf = self;
    
    NSString *hostBundleIdentifier = self.host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    [SUProbeInstallStatus probeInstallerInProgressForHostBundleIdentifier:hostBundleIdentifier completion:^(BOOL installerIsRunning) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SPUUpdater *strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            
            id <SUUpdateDriver> updateDriver;
            if (!installerIsRunning && [strongSelf automaticallyDownloadsUpdates] && [strongSelf allowsAutomaticUpdates] && strongSelf.resumableUpdate == nil) {
                updateDriver =
                [[SUAutomaticUpdateDriver alloc]
                 initWithHost:strongSelf.host
                 sparkleBundle:strongSelf.sparkleBundle
                 updater:strongSelf.delegator
                 userDriver:strongSelf.userDriver
                 updaterDelegate:strongSelf.delegate];
            } else {
                updateDriver =
                [[SUScheduledUpdateDriver alloc]
                 initWithHost:strongSelf.host
                 sparkleBundle:strongSelf.sparkleBundle
                 updater:strongSelf.delegator
                 userDriver:strongSelf.userDriver
                 updaterDelegate:strongSelf.delegate];
            }
            
            [strongSelf checkForUpdatesWithDriver:updateDriver installerInProgress:installerIsRunning];
        });
    }];
}

- (void)checkForUpdates
{
    __weak SPUUpdater *weakSelf = self;
    if (!self.startedUpdater) {
        self.preStartedScheduledUpdateBlock = ^{
            [weakSelf checkForUpdates];
        };
        return;
    }
    
    if (self.driver != nil) {
        return;
    }
    
    id <SUUpdateDriver> theUpdateDriver = [[SUUserInitiatedUpdateDriver alloc] initWithHost:self.host sparkleBundle:self.sparkleBundle updater:self.delegator userDriver:self.userDriver updaterDelegate:self.delegate];
    
    NSString *bundleIdentifier = self.host.bundle.bundleIdentifier;
    assert(bundleIdentifier != nil);
    [SUProbeInstallStatus probeInstallerInProgressForHostBundleIdentifier:bundleIdentifier completion:^(BOOL installerInProgress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SPUUpdater *strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf checkForUpdatesWithDriver:theUpdateDriver installerInProgress:installerInProgress];
            }
        });
    }];
}

- (void)checkForUpdateInformation
{
    __weak SPUUpdater *weakSelf = self;
    if (!self.startedUpdater) {
        self.preStartedScheduledUpdateBlock = ^{
            [weakSelf checkForUpdateInformation];
        };
        return;
    }
    
    NSString *bundleIdentifier = self.host.bundle.bundleIdentifier;
    assert(bundleIdentifier != nil);
    [SUProbeInstallStatus probeInstallerInProgressForHostBundleIdentifier:bundleIdentifier completion:^(BOOL installerInProgress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SPUUpdater *strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf checkForUpdatesWithDriver:[[SUProbingUpdateDriver alloc] initWithHost:strongSelf.host updater:strongSelf.delegator updaterDelegate:strongSelf.delegate] installerInProgress:installerInProgress];
            }
        });
    }];
}

- (void)checkForUpdatesWithDriver:(id <SUUpdateDriver> )d installerInProgress:(BOOL)installerInProgress
{
    if (self.driver != nil) {
        return;
    }
    
    [self.userDriver invalidateUpdateCheckTimer];

    [self updateLastUpdateCheckDate];

    if( [self.delegate respondsToSelector: @selector(updaterMayCheckForUpdates:)] && ![self.delegate updaterMayCheckForUpdates:self.delegator] )
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
    
    // Reload our host bundle information in case its current cache is out of date
    // We could have updated the bundle before for example without terminating this updater process
    [self.host reloadInfoDictionary];

    // Because an application can change the configuration (eg: the feed url) at any point, we should always check if it's valid
    NSError *configurationError = nil;
    if (![self checkIfConfiguredProperly:&configurationError]) {
        // Don't think we should schedule a next update check if the bundle has been misconfigured once,
        // which would mean something is really off
        SULog(@"Sparkle configuration error (%ld): %@", (long)configurationError.code, configurationError.localizedDescription);
        SULog(@"Disabling scheduled updates..");
        
        [self.driver abortUpdateWithError:configurationError];
        self.driver = nil;
        
        return;
    }

    NSURL *theFeedURL = [self parameterizedFeedURL];
    if (theFeedURL) {
        __weak SPUUpdater *weakSelf = self;
        SUUpdateDriverCompletion completionBlock = ^(BOOL shouldShowUpdateImmediately, SUDownloadedUpdate * _Nullable resumableUpdate) {
            SPUUpdater *strongSelf = weakSelf;
            if (strongSelf != nil) {
                strongSelf.resumableUpdate = resumableUpdate;
                strongSelf.driver = nil;
                [strongSelf updateLastUpdateCheckDate];
                [strongSelf scheduleNextUpdateCheckFiringImmediately:shouldShowUpdateImmediately];
            }
        };
        
        [self.userDriver showCanCheckForUpdates:NO];
        
        if (installerInProgress) {
            [self.driver resumeInstallingUpdateWithCompletion:completionBlock];
        } else if (self.resumableUpdate != nil) {
            [self.driver resumeDownloadedUpdate:(SUDownloadedUpdate * _Nonnull)self.resumableUpdate completion:completionBlock];
        } else {
            [self.driver checkForUpdatesAtAppcastURL:theFeedURL withUserAgent:[self userAgentString] httpHeaders:[self httpHeaders] completion:completionBlock];
        }
    } else {
        // I think this is really unlikely to occur but better be safe
        [self.driver abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInvalidFeedURLError userInfo:@{ NSLocalizedDescriptionKey: @"Sparkle cannot form a valid feed URL." }]];
        self.driver = nil;
    }
}

- (void)cancelNextUpdateCycle
{
    [self.updaterCycle cancelNextUpdateCycle];
}

- (void)resetUpdateCycle
{
    if (!self.startedUpdater) {
        return; // not even ready yet
    }
    
    [self cancelNextUpdateCycle];
    
    if (self.driver == nil) {
        [self scheduleNextUpdateCheck];
    }
}

- (void)resetUpdateCycleAfterShortDelay
{
    [self cancelNextUpdateCycle];
    [self.updaterCycle resetUpdateCycleAfterDelay];
}

- (void)setAutomaticallyChecksForUpdates:(BOOL)automaticallyCheckForUpdates
{
    [self.host setBool:automaticallyCheckForUpdates forUserDefaultsKey:SUEnableAutomaticChecksKey];
    // Hack to support backwards compatibility with older Sparkle versions, which supported
    // disabling updates by setting the check interval to 0.
    if (automaticallyCheckForUpdates && (NSInteger)[self updateCheckInterval] == 0) {
        [self setUpdateCheckInterval:SUDefaultUpdateCheckInterval];
    }
    // Provide a small delay in case multiple preferences are being updated simultaneously.
    [self resetUpdateCycleAfterShortDelay];
}

- (BOOL)automaticallyChecksForUpdates
{
    return [self.updaterSettings automaticallyChecksForUpdates];
}

- (void)setAutomaticallyDownloadsUpdates:(BOOL)automaticallyUpdates
{
    [self.host setBool:automaticallyUpdates forUserDefaultsKey:SUAutomaticallyUpdateKey];
}

- (BOOL)automaticallyDownloadsUpdates
{
    return [self.updaterSettings automaticallyDownloadsUpdates];
}

- (BOOL)allowsAutomaticUpdates
{
    return [self.updaterSettings allowsAutomaticUpdates];
}

- (void)setFeedURL:(NSURL *)feedURL
{
    if (![NSThread isMainThread]) {
        SULog(@"This method must be called on the main thread");
        abort();
    }

    [self.host setObject:[feedURL absoluteString] forUserDefaultsKey:SUFeedURLKey];
}

- (BOOL)retrieveFeedURL:(NSURL * __autoreleasing *)feedURL error:(NSError * __autoreleasing *)error
{
    if (![NSThread isMainThread]) {
        SULog(@"This method must be called on the main thread");
        abort();
    }
    
    // A value in the user defaults overrides one in the Info.plist (so preferences panels can be created wherein users choose between beta / release feeds).
    NSString *appcastString = [self.host objectForKey:SUFeedURLKey];
    if ([self.delegate respondsToSelector:@selector(feedURLStringForUpdater:)])
        appcastString = [self.delegate feedURLStringForUpdater:self.delegator];
    
    if (!appcastString) { // Can't find an appcast string!
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInvalidFeedURLError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"You must specify the URL of the appcast as the %@ key in either the Info.plist or the user defaults!", SUFeedURLKey] }];
        }
        return NO;
    }
    
    NSCharacterSet *quoteSet = [NSCharacterSet characterSetWithCharactersInString:@"\"\'"]; // Some feed publishers add quotes; strip 'em.
    NSString *castUrlStr = [appcastString stringByTrimmingCharactersInSet:quoteSet];
    if (feedURL != NULL) {
        if (!castUrlStr || [castUrlStr length] == 0) {
            *feedURL =  nil;
        } else {
            *feedURL = [NSURL URLWithString:castUrlStr];
        }
    }
    return YES;
}

// A client may call this method but do not invoke this method ourselves because its unsafe
- (NSURL *)feedURL
{
    NSURL *feedURL = nil;
    NSError *feedError = nil;
    if (![self retrieveFeedURL:&feedURL error:&feedError]) {
        SULog(@"Fatal Feed Error (%ld): %@", feedError.code, feedError.localizedDescription);
        abort();
    }
    return feedURL;
}

- (NSString *)userAgentString
{
    if (customUserAgentString) {
        return customUserAgentString;
    }

    NSString *version = [self.sparkleBundle objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey];
    NSString *userAgent = [NSString stringWithFormat:@"%@/%@ Sparkle/%@", [self.host name], [self.host displayVersion], version ? version : @"?"];
    NSData *cleanedAgent = [userAgent dataUsingEncoding:NSASCIIStringEncoding allowLossyConversion:YES];
    
    NSString *result = @"";
    if (cleanedAgent != nil) {
        NSString *cleanedAgentString = [[NSString alloc] initWithData:(NSData * _Nonnull)cleanedAgent encoding:NSASCIIStringEncoding];
        if (cleanedAgentString != nil) {
            result = cleanedAgentString;
        }
    }
    
    return result;
}

- (void)setSendsSystemProfile:(BOOL)sendsSystemProfile
{
    [self.host setBool:sendsSystemProfile forUserDefaultsKey:SUSendProfileInfoKey];
}

- (BOOL)sendsSystemProfile
{
    return [self.updaterSettings sendsSystemProfile];
}

// Precondition: The feed URL should be valid
- (NSURL * _Nullable)parameterizedFeedURL
{
    NSURL *baseFeedURL = nil;
    if (![self retrieveFeedURL:&baseFeedURL error:NULL]) {
        SULog(@"Unexpected error: base feed URL is invalid during -parameterizedFeedURL");
        return nil;
    }
    
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
        NSArray *feedParameters = [self.delegate feedParametersForUpdater:self.delegator sendingSystemProfile:sendingSystemProfile];
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
        [parameterStrings addObject:[NSString stringWithFormat:@"%@=%@", [[[currentProfileInfo objectForKey:@"key"] description] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding], [[[currentProfileInfo objectForKey:@"value"] description] stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];
    }

    NSString *separatorCharacter = @"?";
    if ([baseFeedURL query]) {
        separatorCharacter = @"&"; // In case the URL is already http://foo.org/baz.xml?bat=4
    }
    NSString *appcastStringWithProfile = [NSString stringWithFormat:@"%@%@%@", [baseFeedURL absoluteString], separatorCharacter, [parameterStrings componentsJoinedByString:@"&"]];

    // Clean it up so it's a valid URL
    NSURL *parameterizedFeedURL = [NSURL URLWithString:appcastStringWithProfile];
    if (parameterizedFeedURL == nil) {
        SULog(@"Unexpected error: parameterized feed URL formed from %@ is invalid", appcastStringWithProfile);
    }
    return parameterizedFeedURL;
}

- (void)setUpdateCheckInterval:(NSTimeInterval)updateCheckInterval
{
    [self.host setObject:@(updateCheckInterval) forUserDefaultsKey:SUScheduledCheckIntervalKey];
    if ((NSInteger)updateCheckInterval == 0) { // For compatibility with 1.1's settings.
        [self setAutomaticallyChecksForUpdates:NO];
    }
    // Provide a small delay in case multiple preferences are being updated simultaneously.
    [self resetUpdateCycleAfterShortDelay];
}

- (NSTimeInterval)updateCheckInterval
{
    return [self.updaterSettings updateCheckInterval];
}

// This may not return the same update check interval as the developer has configured
// Notably it may differ when we have an update that has been already downloaded and needs to resume,
// as well as if that update is marked critical or not
- (void)retrieveNextUpdateCheckInterval:(void (^)(NSTimeInterval))completionHandler
{
    NSString *hostBundleIdentifier = self.host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    [SUProbeInstallStatus probeInstallerUpdateItemForHostBundleIdentifier:hostBundleIdentifier completion:^(SPUInstallationInfo * _Nullable installationInfo) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSTimeInterval regularCheckInterval = [self updateCheckInterval];
            if (installationInfo == nil) {
                // Proceed as normal if there's no resumable updates
                completionHandler(regularCheckInterval);
            } else {
                if (!installationInfo.canSilentlyInstall || [installationInfo.appcastItem isCriticalUpdate]) {
                    completionHandler(MIN(regularCheckInterval, SUImpatientUpdateCheckInterval));
                } else {
                    completionHandler(MAX(regularCheckInterval, SUImpatientUpdateCheckInterval));
                }
            }
        });
    }];
}

- (void)dealloc
{
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

- (NSBundle *)hostBundle { return [self.host bundle]; }

// Private API for backwards compatibility, used by SUUpdater
- (void)setDelegate:(id<SUUpdaterDelegate>)delegate
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"
    // Don't want to declare a property for a private API
    _delegate = delegate;
#pragma clang diagnostic pop
}

// Private API for backwards compatibility, used by SUUpdater
- (void)setUpdaterDelegator:(id)delegator
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"
    // Don't want to declare a property for a private API
    _delegator = delegator;
#pragma clang diagnostic pop
}

@end
