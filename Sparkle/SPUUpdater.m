//
//  SPUUpdater.m
//  Sparkle
//
//  Created by Andy Matuschak on 1/4/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SPUUpdater.h"
#import "SPUUpdaterDelegate.h"
#import "SPUUpdaterSettings.h"
#import "SUHost.h"
#import "SPUUpdatePermissionRequest.h"
#import "SUUpdatePermissionResponse.h"
#import "SPUUpdateDriver.h"
#import "SUConstants.h"
#import "SULog.h"
#import "SUCodeSigningVerifier.h"
#import "SUSystemProfiler.h"
#import "SPUScheduledUpdateDriver.h"
#import "SPUProbingUpdateDriver.h"
#import "SPUUserInitiatedUpdateDriver.h"
#import "SPUAutomaticUpdateDriver.h"
#import "SPUProbeInstallStatus.h"
#import "SUAppcastItem.h"
#import "SPUInstallationInfo.h"
#import "SUErrors.h"
#import "SPUXPCServiceInfo.h"
#import "SPUUpdaterCycle.h"
#import "SPUUpdaterTimer.h"
#import "SPUResumableUpdate.h"
#import "SUSignatures.h"


#include "AppKitPrevention.h"

NSString *const SUUpdaterDidFinishLoadingAppCastNotification = @"SUUpdaterDidFinishLoadingAppCastNotification";
NSString *const SUUpdaterDidFindValidUpdateNotification = @"SUUpdaterDidFindValidUpdateNotification";
NSString *const SUUpdaterDidNotFindUpdateNotification = @"SUUpdaterDidNotFindUpdateNotification";
NSString *const SUUpdaterWillRestartNotification = @"SUUpdaterWillRestartNotificationName";
NSString *const SUUpdaterAppcastItemNotificationKey = @"SUUpdaterAppcastItemNotificationKey";
NSString *const SUUpdaterAppcastNotificationKey = @"SUUpdaterAppCastNotificationKey";

@interface SPUUpdater () <SPUUpdaterCycleDelegate, SPUUpdaterTimerDelegate>

@property (readonly, copy) NSURL *parameterizedFeedURL;

@property (nonatomic, readonly) id<SPUUserDriver> userDriver;
@property (weak, readonly, nullable) id<SPUUpdaterDelegate> delegate;
@property (nonatomic) id <SPUUpdateDriver> driver;
@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, readonly) NSBundle *applicationBundle;
@property (nonatomic, readonly) SPUUpdaterSettings *updaterSettings;
@property (nonatomic, readonly) SPUUpdaterCycle *updaterCycle;
@property (nonatomic, readonly) SPUUpdaterTimer *updaterTimer;
@property (nonatomic) BOOL startedUpdater;
@property (nonatomic, copy) void (^preStartedScheduledUpdateBlock)(void);
@property (nonatomic, nullable) id<SPUResumableUpdate> resumableUpdate;

@property (nonatomic) BOOL loggedATSWarning;
@property (nonatomic) BOOL loggedDSAWarning;

@end

@implementation SPUUpdater

@synthesize delegate = _delegate;
@synthesize userDriver = _userDriver;
@synthesize userAgentString = customUserAgentString;
@synthesize httpHeaders;
@synthesize driver;
@synthesize host = _host;
@synthesize applicationBundle = _applicationBundle;
@synthesize updaterSettings = _updaterSettings;
@synthesize updaterCycle = _updaterCycle;
@synthesize updaterTimer = _updaterTimer;
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

- (instancetype)initWithHostBundle:(NSBundle *)hostBundle applicationBundle:(NSBundle *)applicationBundle userDriver:(id <SPUUserDriver>)userDriver delegate:(id<SPUUpdaterDelegate> _Nullable)delegate
{
    self = [super init];
    
    if (self != nil) {
        // Use explicit class to use the correct bundle even when subclassed
        _sparkleBundle = [NSBundle bundleForClass:[SPUUpdater class]];
        
        _host = [[SUHost alloc] initWithBundle:hostBundle];
        _applicationBundle = applicationBundle;
        
        _updaterSettings = [[SPUUpdaterSettings alloc] initWithHostBundle:hostBundle];
        _updaterCycle = [[SPUUpdaterCycle alloc] initWithDelegate:self];
        _updaterTimer = [[SPUUpdaterTimer alloc] initWithDelegate:self];
        
        _userDriver = userDriver;
        
        _delegate = delegate;
    }
    
    return self;
}

// To prevent subclasses from doing something bad based on older Sparkle code
- (instancetype)initForBundle:(NSBundle *)__unused bundle
{
    NSString *reason = [NSString stringWithFormat:@"-[%@ initForBundle:] is not implemented anymore in Sparkle 2.", NSStringFromClass([self class])];
    SULog(SULogLevelError, @"%@", reason);
    
    NSException *exception = [NSException exceptionWithName:@"SUIncorrectAPIUsageException" reason:reason userInfo:nil];
    @throw exception;
    
    return nil;
}

// To prevent trying to stick an SUUpdater in a nib or initializing it in an incorrect way
- (instancetype)init
{
    NSString *reason = [NSString stringWithFormat:@"-[%@ init] is not implemented. If you want to drop an updater into a nib, see SPUStandardUpdaterController.", NSStringFromClass([self class])];
    SULog(SULogLevelError, @"%@", reason);
    
    NSException *exception = [NSException exceptionWithName:@"SUIncorrectAPIUsageException" reason:reason userInfo:nil];
    @throw exception;
    
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
        BOOL foundXPCPersistentDownloaderService = NO;
        BOOL foundATSPersistentIssue = [self checkATSIssueForBundle:SPUXPCServiceBundle(@DOWNLOADER_BUNDLE_ID) getBundleExists:&foundXPCPersistentDownloaderService];
        
        NSBundle *mainBundle = [NSBundle mainBundle];
        BOOL foundATSMainBundleIssue = NO;
        if (!foundATSPersistentIssue && !foundXPCPersistentDownloaderService) {
            BOOL foundATSIssue = ([mainBundle objectForInfoDictionaryKey:@"NSAppTransportSecurity"] == nil);
            BOOL updatingMainBundle = [self.host.bundle isEqualTo:mainBundle];
            
            if (updatingMainBundle) {
                // The only way we'll know for sure if there is an issue is if the main bundle is the same as the one we're updating
                // We don't want to generate false positives..
                foundATSMainBundleIssue = foundATSIssue;
            }
        }
        
        if (foundATSPersistentIssue || foundATSMainBundleIssue) {
            if (!self.loggedATSWarning) {
                // Just log a warning. Don't outright fail in case we are wrong (eg: app is linked on an old SDK where ATS doesn't take effect)
                SULog(SULogLevelDefault, @"The feed URL (%@) may need to change to use HTTPS.\nFor more information: https://sparkle-project.org/documentation/app-transport-security", [feedURL absoluteString]);
                
                self.loggedATSWarning = YES;
            }
        }
    }
    
    BOOL hasPublicKey = self.host.publicKeys.hasAnyKeys;
    if (!hasPublicKey) {
        // If we failed to retrieve a DSA key but the bundle specifies a path to one, we should consider this a configuration failure
        NSString *publicDSAKeyFileKey = [self.host publicDSAKeyFileKey];
        if (publicDSAKeyFileKey != nil) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUNoPublicDSAFoundError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The DSA public key '%@' could not be found.", publicDSAKeyFileKey] }];
            }
            return NO;
        }
    }

    if (!hasPublicKey) {
        if (!servingOverHttps || ![SUCodeSigningVerifier bundleAtURLIsCodeSigned:[[self hostBundle] bundleURL]]) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUNoPublicDSAFoundError userInfo:@{ NSLocalizedDescriptionKey: @"For security reasons, updates need to be signed with an EdDSA key. See Sparkle's documentation for more information." }];
            }
            return NO;
        } else {
            if (!self.loggedDSAWarning) {
                // Deprecated because we pass the downloaded archive to the installer and the installer has no way of knowing where the download came from.
                // Even if it did, the server and the download on it could still be compromised. But if a DSA signature was used, the private key should
                // not be stored on the server serving the update
                SULog(SULogLevelDefault, @"DEPRECATION: Serving updates without an EdDSA key is now deprecated and may be removed from a future release. See Sparkle's documentation for more information.");
                
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
    BOOL hasLaunchedBefore = [self.host boolForUserDefaultsKey:SUHasLaunchedBeforeKey];

    // If the user has been asked about automatic checks, don't bother prompting
    // When the user answers to the permission prompt, this will be set to either @YES or @NO instead of nil
    if ([self.host objectForUserDefaultsKey:SUEnableAutomaticChecksKey] != nil) {
        shouldPrompt = NO;
    }
    // If the developer wants to check for updates, we shouldn't bug the user about a prompt yet
    else if (self.preStartedScheduledUpdateBlock != nil) {
        shouldPrompt = NO;
    }
    // Does the delegate want to take care of the logic for when we should ask permission to update?
    else if ([self.delegate respondsToSelector:@selector((updaterShouldPromptForPermissionToCheckForUpdates:))]) {
        shouldPrompt = [self.delegate updaterShouldPromptForPermissionToCheckForUpdates:self];
    }
    // Has the user been asked already? And don't ask if the host has a default value set in its Info.plist.
    else if ([self.host objectForKey:SUEnableAutomaticChecksKey] == nil) {
        // We wait until the second launch of the updater for this host bundle, unless explicitly overridden via SUPromptUserOnFirstLaunchKey.
        shouldPrompt = [self.host objectForKey:SUPromptUserOnFirstLaunchKey] || hasLaunchedBefore;
    }
    
    if (!hasLaunchedBefore) {
        [self.host setBool:YES forUserDefaultsKey:SUHasLaunchedBeforeKey];
    }

    if (shouldPrompt) {
        NSArray<NSDictionary<NSString *, NSString *> *> *profileInfo = [SUSystemProfiler systemProfileArrayForHost:self.host];
        // Always say we're sending the system profile here so that the delegate displays the parameters it would send.
        if ([self.delegate respondsToSelector:@selector((feedParametersForUpdater:sendingSystemProfile:))]) {
            NSArray *feedParameters = [self.delegate feedParametersForUpdater:self sendingSystemProfile:YES];
            if (feedParameters != nil) {
                profileInfo = [profileInfo arrayByAddingObjectsFromArray:feedParameters];
            }
        }
        
        SPUUpdatePermissionRequest *updatePermissionRequest = [[SPUUpdatePermissionRequest alloc] initWithSystemProfile:profileInfo];
        
        __weak SPUUpdater *weakSelf = self;
        [self.userDriver showUpdatePermissionRequest:updatePermissionRequest reply:^(SUUpdatePermissionResponse *response) {
            dispatch_async(dispatch_get_main_queue(), ^{
                SPUUpdater *strongSelf = weakSelf;
                if (strongSelf != nil) {
                    [strongSelf updatePermissionRequestFinishedWithResponse:response];
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

- (void)updatePermissionRequestFinishedWithResponse:(SUUpdatePermissionResponse *)response
{
    [self setSendsSystemProfile:response.sendSystemProfile];
    [self setAutomaticallyChecksForUpdates:response.automaticUpdateChecks];
}

- (NSDate *)lastUpdateCheckDate
{
    return [self.host objectForUserDefaultsKey:SULastCheckTimeKey];
}

- (void)updateLastUpdateCheckDate
{
    [self willChangeValueForKey:NSStringFromSelector(@selector((lastUpdateCheckDate)))];
    [self.host setObject:[NSDate date] forUserDefaultsKey:SULastCheckTimeKey];
    [self didChangeValueForKey:NSStringFromSelector(@selector((lastUpdateCheckDate)))];
}

- (void)scheduleNextUpdateCheck
{
    [self scheduleNextUpdateCheckFiringImmediately:NO];
}

- (void)scheduleNextUpdateCheckFiringImmediately:(BOOL)firingImmediately
{
    [self.updaterTimer invalidate];
    
    BOOL automaticallyCheckForUpdates = [self automaticallyChecksForUpdates];
    
    [self.userDriver showCanCheckForUpdates:!automaticallyCheckForUpdates];
    
    if (!automaticallyCheckForUpdates) {
        if ([self.delegate respondsToSelector:@selector(updaterWillIdleSchedulingUpdates:)]) {
            [self.delegate updaterWillIdleSchedulingUpdates:self];
        }
        return;
    }
    
    if (firingImmediately) {
        [self checkForUpdatesInBackground];
    } else {
        [self.userDriver showCanCheckForUpdates:YES];
        
        [self retrieveNextUpdateCheckInterval:^(NSTimeInterval updateCheckInterval) {
            // This callback is asynchronous, so the timer may be set. Invalidate to make sure it isn't.
            [self.updaterTimer invalidate];
            
            // How long has it been since last we checked for an update?
            NSDate *lastCheckDate = [self lastUpdateCheckDate];
            if (!lastCheckDate) { lastCheckDate = [NSDate distantPast]; }
            NSTimeInterval intervalSinceCheck = [[NSDate date] timeIntervalSinceDate:lastCheckDate];
            
            // Now we want to figure out how long until we check again.
            if (updateCheckInterval < SUMinimumUpdateCheckInterval)
                updateCheckInterval = SUMinimumUpdateCheckInterval;
            if (intervalSinceCheck < updateCheckInterval) {
                NSTimeInterval delayUntilCheck = (updateCheckInterval - intervalSinceCheck); // It hasn't been long enough.
                if ([self.delegate respondsToSelector:@selector(updater:willScheduleUpdateCheckAfterDelay:)]) {
                    [self.delegate updater:self willScheduleUpdateCheckAfterDelay:delayUntilCheck];
                }
                [self.updaterTimer startAndFireAfterDelay:delayUntilCheck];
            } else {
                // We're overdue! Run one now.
                [self checkForUpdatesInBackground];
            }
        }];
    }
}

- (void)updaterTimerDidFire
{
    [self checkForUpdatesInBackground];
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
    [SPUProbeInstallStatus probeInstallerInProgressForHostBundleIdentifier:hostBundleIdentifier completion:^(BOOL installerIsRunning) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SPUUpdater *strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            
            id <SPUUpdateDriver> updateDriver;
            if (!installerIsRunning && [strongSelf automaticallyDownloadsUpdates] && strongSelf.resumableUpdate == nil) {
                updateDriver =
                [[SPUAutomaticUpdateDriver alloc]
                 initWithHost:strongSelf.host
                 applicationBundle:strongSelf.applicationBundle
                 sparkleBundle:strongSelf.sparkleBundle
                 updater:strongSelf
                 userDriver:strongSelf.userDriver
                 updaterDelegate:strongSelf.delegate];
            } else {
                updateDriver =
                [[SPUScheduledUpdateDriver alloc]
                 initWithHost:strongSelf.host
                 applicationBundle:strongSelf.applicationBundle
                 sparkleBundle:strongSelf.sparkleBundle
                 updater:strongSelf
                 userDriver:strongSelf.userDriver
                 updaterDelegate:strongSelf.delegate];
            }
            
            BOOL preventsInstallerInteraction;
            if ([strongSelf.delegate respondsToSelector:@selector(updater:shouldAllowInstallerInteractionForUpdateCheck:)]) {
                preventsInstallerInteraction = ![strongSelf.delegate updater:strongSelf shouldAllowInstallerInteractionForUpdateCheck:SPUUpdateCheckBackgroundScheduled];
            } else {
                preventsInstallerInteraction = NO;
            }
            
            [strongSelf checkForUpdatesWithDriver:updateDriver installerInProgress:installerIsRunning preventsInstallerInteraction:preventsInstallerInteraction];
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
    
    id <SPUUpdateDriver> theUpdateDriver = [[SPUUserInitiatedUpdateDriver alloc] initWithHost:self.host applicationBundle:self.applicationBundle sparkleBundle:self.sparkleBundle updater:self userDriver:self.userDriver updaterDelegate:self.delegate];
    
    NSString *bundleIdentifier = self.host.bundle.bundleIdentifier;
    assert(bundleIdentifier != nil);
    [SPUProbeInstallStatus probeInstallerInProgressForHostBundleIdentifier:bundleIdentifier completion:^(BOOL installerInProgress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SPUUpdater *strongSelf = weakSelf;
            if (strongSelf != nil) {
                BOOL preventsInstallerInteraction;
                if ([strongSelf.delegate respondsToSelector:@selector(updater:shouldAllowInstallerInteractionForUpdateCheck:)]) {
                    preventsInstallerInteraction = ![strongSelf.delegate updater:strongSelf shouldAllowInstallerInteractionForUpdateCheck:SPUUpdateCheckUserInitiated];
                } else {
                    preventsInstallerInteraction = NO;
                }
                
                [strongSelf checkForUpdatesWithDriver:theUpdateDriver installerInProgress:installerInProgress preventsInstallerInteraction:preventsInstallerInteraction];
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
    [SPUProbeInstallStatus probeInstallerInProgressForHostBundleIdentifier:bundleIdentifier completion:^(BOOL installerInProgress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SPUUpdater *strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf checkForUpdatesWithDriver:[[SPUProbingUpdateDriver alloc] initWithHost:strongSelf.host updater:strongSelf updaterDelegate:strongSelf.delegate] installerInProgress:installerInProgress preventsInstallerInteraction:NO];
            }
        });
    }];
}

- (void)checkForUpdatesWithDriver:(id <SPUUpdateDriver> )d installerInProgress:(BOOL)installerInProgress preventsInstallerInteraction:(BOOL)preventsInstallerInteraction
{
    if (self.driver != nil) {
        return;
    }
    
    [self.updaterTimer invalidate];

    [self updateLastUpdateCheckDate];

    if( [self.delegate respondsToSelector: @selector((updaterMayCheckForUpdates:))] && ![self.delegate updaterMayCheckForUpdates:self] )
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

    // Because an application can change the configuration (eg: the feed url) at any point, we should always check if it's valid
    NSError *configurationError = nil;
    if (![self checkIfConfiguredProperly:&configurationError]) {
        // Don't think we should schedule a next update check if the bundle has been misconfigured once,
        // which would mean something is really off
        SULog(SULogLevelError, @"Sparkle configuration error (%ld): %@", (long)configurationError.code, configurationError.localizedDescription);
        SULog(SULogLevelDefault, @"Disabling scheduled updates..");
        
        [self.driver abortUpdateWithError:configurationError];
        self.driver = nil;
        
        return;
    }

    NSURL *theFeedURL = [self parameterizedFeedURL];
    if (theFeedURL) {
        __weak SPUUpdater *weakSelf = self;
        SPUUpdateDriverCompletion completionBlock = ^(BOOL shouldShowUpdateImmediately, id<SPUResumableUpdate> _Nullable resumableUpdate) {
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
            [self.driver resumeUpdate:(id<SPUResumableUpdate> _Nonnull)self.resumableUpdate completion:completionBlock];
        } else {
            [self.driver checkForUpdatesAtAppcastURL:theFeedURL withUserAgent:[self userAgentString] httpHeaders:[self httpHeaders] preventingInstallerInteraction:preventsInstallerInteraction completion:completionBlock];
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
    return [self.updaterSettings allowsAutomaticUpdates] && [self.updaterSettings automaticallyDownloadsUpdates];
}

- (void)setFeedURL:(NSURL * _Nullable)feedURL
{
    if (![NSThread isMainThread]) {
        SULog(SULogLevelError, @"Error: SPUUpdater -setFeedURL: must be called on the main thread. The call from a background thread was ignored.");
        return;
    }

    // When feedURL is nil, -absoluteString will return nil and will remove the user default key
    [self.host setObject:[feedURL absoluteString] forUserDefaultsKey:SUFeedURLKey];
}

- (BOOL)retrieveFeedURL:(NSURL * __autoreleasing *)feedURL error:(NSError * __autoreleasing *)error
{
    if (![NSThread isMainThread]) {
        SULog(SULogLevelError, @"Error: SPUUpdater -retrieveFeedURL:error: must be called on the main thread.");
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUIncorrectAPIUsageError userInfo:@{ NSLocalizedDescriptionKey: @"SUUpdater -retriveFeedURL:error: must be called on the main thread."}];
        }
        return NO;
    }
    
    // A value in the user defaults overrides one in the Info.plist (so preferences panels can be created wherein users choose between beta / release feeds).
    NSString *appcastString = [self.host objectForKey:SUFeedURLKey];
    if ([self.delegate respondsToSelector:@selector((feedURLStringForUpdater:))]) {
        NSString *delegateAppcastString = [self.delegate feedURLStringForUpdater:self];
        if (delegateAppcastString != nil) {
            appcastString = delegateAppcastString;
        }
    }
    
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

// A client may call this method but do not invoke this method ourselves because it's unsafe
- (NSURL *)feedURL
{
    NSURL *feedURL = nil;
    NSError *feedError = nil;
    if (![self retrieveFeedURL:&feedURL error:&feedError]) {
        SULog(SULogLevelError, @"Feed Error (%ld): %@", feedError.code, feedError.localizedDescription);
        return nil;
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

static NSString *escapeURLComponent(NSString *str) {
    return [[[[str stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]
             stringByReplacingOccurrencesOfString:@"=" withString:@"%3d"]
             stringByReplacingOccurrencesOfString:@"&" withString:@"%26"]
             stringByReplacingOccurrencesOfString:@"+" withString:@"%2b"];
}

// Precondition: The feed URL should be valid
- (NSURL * _Nullable)parameterizedFeedURL
{
    NSURL *baseFeedURL = nil;
    if (![self retrieveFeedURL:&baseFeedURL error:NULL]) {
        SULog(SULogLevelError, @"Unexpected error: base feed URL is invalid during -parameterizedFeedURL");
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

    NSArray<NSDictionary<NSString *, NSString *> *> *parameters = @[];
    if ([self.delegate respondsToSelector:@selector((feedParametersForUpdater:sendingSystemProfile:))]) {
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
    for (NSDictionary<NSString *, NSString *> *currentProfileInfo in parameters) {
        [parameterStrings addObject:[NSString stringWithFormat:@"%@=%@", escapeURLComponent([[currentProfileInfo objectForKey:@"key"] description]), escapeURLComponent([[currentProfileInfo objectForKey:@"value"] description])]];
    }

    NSString *separatorCharacter = @"?";
    if ([baseFeedURL query]) {
        separatorCharacter = @"&"; // In case the URL is already http://foo.org/baz.xml?bat=4
    }
    NSString *appcastStringWithProfile = [NSString stringWithFormat:@"%@%@%@", [baseFeedURL absoluteString], separatorCharacter, [parameterStrings componentsJoinedByString:@"&"]];

    // Clean it up so it's a valid URL
    NSURL *parameterizedFeedURL = [NSURL URLWithString:appcastStringWithProfile];
    if (parameterizedFeedURL == nil) {
        SULog(SULogLevelError, @"Unexpected error: parameterized feed URL formed from %@ is invalid", appcastStringWithProfile);
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
    [SPUProbeInstallStatus probeInstallerUpdateItemForHostBundleIdentifier:hostBundleIdentifier completion:^(SPUInstallationInfo * _Nullable installationInfo) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSTimeInterval regularCheckInterval = [self updateCheckInterval];
            if (installationInfo == nil) {
                // Proceed as normal if there's no resumable updates
                completionHandler(regularCheckInterval);
            } else {
                if (!installationInfo.canSilentlyInstall || [installationInfo.appcastItem isCriticalUpdate] || [installationInfo.appcastItem isInformationOnlyUpdate]) {
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
    [self.updaterTimer invalidate];
    
    // Abort any on-going updates
    // A driver could be retained by another object (eg: a timer),
    // so not aborting could mean it stays alive longer than we'd want
    [self.driver abortUpdate];
    self.driver = nil;
}

- (NSBundle *)hostBundle { return [self.host bundle]; }

@end
