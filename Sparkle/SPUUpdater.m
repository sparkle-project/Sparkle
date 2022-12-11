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
#import "SULog+NSError.h"
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
#import "SPUUserAgent+Private.h"
#import "SPUGentleUserDriverReminders.h"


#include "AppKitPrevention.h"

NSString *const SUUpdaterDidFinishLoadingAppCastNotification = @"SUUpdaterDidFinishLoadingAppCastNotification";
NSString *const SUUpdaterDidFindValidUpdateNotification = @"SUUpdaterDidFindValidUpdateNotification";
NSString *const SUUpdaterDidNotFindUpdateNotification = @"SUUpdaterDidNotFindUpdateNotification";
NSString *const SUUpdaterWillRestartNotification = @"SUUpdaterWillRestartNotificationName";
NSString *const SUUpdaterAppcastItemNotificationKey = @"SUUpdaterAppcastItemNotificationKey";
NSString *const SUUpdaterAppcastNotificationKey = @"SUUpdaterAppCastNotificationKey";

@interface SPUUpdater () <SPUUpdaterCycleDelegate, SPUUpdaterTimerDelegate>

// These two properties are needed for KVO
@property (nonatomic) BOOL sessionInProgress;
@property (nonatomic) BOOL canCheckForUpdates;

@end

@implementation SPUUpdater
{
    id<SPUUserDriver> _userDriver;
    id <SPUUpdateDriver> _driver;
    SUHost *_host;
    SUHost *_mainBundleHost;
    NSBundle *_applicationBundle;
    NSBundle *_sparkleBundle;
    SPUUpdaterSettings *_updaterSettings;
    SPUUpdaterCycle *_updaterCycle;
    SPUUpdaterTimer *_updaterTimer;
    id<SPUResumableUpdate> _resumableUpdate;
    NSDate *_updateLastCheckedDate;
    NSURL *_parameterizedFeedURL;
    
    __weak id<SPUUpdaterDelegate> _delegate;
    
    BOOL _startedUpdater;
    BOOL _sessionInProgress;
    BOOL _canCheckForUpdates;
    BOOL _showingPermissionRequest;
    BOOL _loggedATSWarning;
    BOOL _loggedNoSecureKeyWarning;
}

@synthesize userAgentString = _userAgentString;
@synthesize httpHeaders = _httpHeaders;
@synthesize sessionInProgress = _sessionInProgress;
@synthesize canCheckForUpdates = _canCheckForUpdates;

#if DEBUG
+ (void)initialize
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // We're using NSLog instead of SULog here because we don't want to start Sparkle's logger here,
        // and because this is not really an error, just a warning notice
        NSLog(@"WARNING: This is running a Debug build of Sparkle 2; don't use this in production!");
    });
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
        
        // Set up default user agent
        // Use the main bundle rather than the bundle to update for retrieving user agent information from
        // We want the user agent to reflect the updater that is doing the updating
        SUHost *mainBundleHost = [[SUHost alloc] initWithBundle:[NSBundle mainBundle]];
        _userAgentString = SPUMakeUserAgentWithHost(mainBundleHost, nil);
        _mainBundleHost = mainBundleHost;
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
    if (_startedUpdater) {
        return YES;
    }
    
    if (![self checkIfConfiguredProperlyAndRequireFeedURL:NO validateXPCServices:YES error:error]) {
        return NO;
    }
    
    if ([_userDriver respondsToSelector:@selector(resetTimeSinceOpportuneUpdateNotice)]) {
        [(id<SPUGentleUserDriverReminders>)_userDriver resetTimeSinceOpportuneUpdateNotice];
    }
    
    _startedUpdater = YES;
    [self setCanCheckForUpdates:YES];
    
    // Start updater on next update cycle so we make sure the application invoking the updater is ready
    // This also gives the developer a cycle to check for updates before Sparkle's update cycle scheduler kicks in
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self->_sessionInProgress) {
            [self startUpdateCycle];
        }
    });
    
    return YES;
}

- (BOOL)checkATSIssueForBundle:(NSBundle * _Nullable)bundle getBundleExists:(BOOL *)bundleExists __attribute__((objc_direct))
{
    if (bundleExists != NULL) {
        *bundleExists = (bundle != nil);
    }
    
    if (bundle == nil) {
        return NO;
    }
    
    return ([bundle objectForInfoDictionaryKey:@"NSAppTransportSecurity"] == nil);
}

- (BOOL)checkIfConfiguredProperlyAndRequireFeedURL:(BOOL)requireFeedURL validateXPCServices:(BOOL)validateXPCServices error:(NSError * __autoreleasing *)error __attribute__((objc_direct))
{
    NSString *hostName = _host.name;
    
    if (_sparkleBundle == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInvalidUpdaterError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ can't find Sparkle.framework it belongs to in %@.", NSStringFromClass([self class]), hostName] }];
        }
        return NO;
    }
    
    if ([[self hostBundle] bundleIdentifier] == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInvalidHostBundleIdentifierError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Sparkle cannot target a bundle that does not have a valid bundle identifier for %@.", hostName] }];
        }
        return NO;
    }
    
    if (!_host.validVersion) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInvalidHostVersionError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Sparkle cannot target a bundle that does not have a valid version for %@.", hostName] }];
        }
        return NO;
    }
    
    SUHost *mainBundleHost = _mainBundleHost;
    if (validateXPCServices) {
        // Check that all enabled XPC Services are embedded
        NSArray<NSString *> *xpcServiceIDs = @[@INSTALLER_LAUNCHER_NAME, @DOWNLOADER_NAME, @INSTALLER_CONNECTION_NAME, @INSTALLER_STATUS_NAME];
        NSArray<NSString *> *xpcServiceEnabledKeys = @[SUEnableInstallerLauncherServiceKey, SUEnableDownloaderServiceKey, SUEnableInstallerConnectionServiceKey, SUEnableInstallerStatusServiceKey];
        NSUInteger xpcServiceCount = xpcServiceIDs.count;
        
        for (NSUInteger xpcServiceIndex = 0; xpcServiceIndex < xpcServiceCount; xpcServiceIndex++) {
            NSString *xpcServiceEnabledKey = xpcServiceEnabledKeys[xpcServiceIndex];
            NSString *xpcServiceBundleName = [xpcServiceIDs[xpcServiceIndex] stringByAppendingPathExtension:@"xpc"];
            
            if ([mainBundleHost boolForInfoDictionaryKey:xpcServiceEnabledKey]) {
                NSURL *xpcServiceBundleURL = [[_sparkleBundle.bundleURL URLByAppendingPathComponent:@"XPCServices"] URLByAppendingPathComponent:xpcServiceBundleName];
                
                if (![xpcServiceBundleURL checkResourceIsReachableAndReturnError:NULL]) {
                    if (error != NULL) {
                        *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInvalidUpdaterError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"XPC Service is enabled (%@) but does not exist: %@", xpcServiceEnabledKey, xpcServiceBundleURL.path] }];
                    }
                    
                    return NO;
                }
            }
            
            // Make sure the app isn't bundling XPC Services directly
            NSURL *mainBundleXPCServiceURL = [[[mainBundleHost.bundle.bundleURL URLByAppendingPathComponent:@"Contents"] URLByAppendingPathComponent:@"XPCServices"] URLByAppendingPathComponent:xpcServiceBundleName];
            
            if ([mainBundleXPCServiceURL checkResourceIsReachableAndReturnError:NULL]) {
                if (error != NULL) {
                    *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInvalidUpdaterError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"XPC Service (%@) must be in the Sparkle framework, not in the application bundle (%@). Please visit https://sparkle-project.org/documentation/sandboxing/ for up to date Sandboxing instructions.", xpcServiceBundleName, mainBundleXPCServiceURL.path] }];
                }
                
                return NO;
            }
        }
    }
    
    BOOL servingOverHttps = NO;
    NSError *feedError = nil;
    NSURL *feedURL = [self retrieveFeedURL:&feedError];
    if (feedURL == nil) {
        if (requireFeedURL) {
            if (error != NULL) {
                *error = feedError;
            }
            return NO;
        }
    }
    
    BOOL updatingMainBundle = [_host.bundle isEqualTo:mainBundleHost.bundle];
    
    if (feedURL != nil) {
        servingOverHttps = [[[feedURL scheme] lowercaseString] isEqualToString:@"https"];
        if (!servingOverHttps && !_loggedATSWarning) {
            BOOL foundXPCDownloaderService = NO;
            
            NSBundle *downloaderBundle;
            if ([mainBundleHost boolForInfoDictionaryKey:SUEnableDownloaderServiceKey]) {
                NSURL *downloaderServiceBundleURL = [[[_sparkleBundle.bundleURL URLByAppendingPathComponent:@"XPCServices"] URLByAppendingPathComponent:@DOWNLOADER_NAME] URLByAppendingPathExtension:@"xpc"];
                downloaderBundle = [NSBundle bundleWithURL:downloaderServiceBundleURL];
            } else {
                downloaderBundle = nil;
            }
            
            BOOL foundATSPersistentIssue = [self checkATSIssueForBundle:downloaderBundle getBundleExists:&foundXPCDownloaderService];
            
            BOOL foundATSMainBundleIssue = NO;
            if (!foundATSPersistentIssue && !foundXPCDownloaderService) {
                BOOL foundATSIssue = ([mainBundleHost objectForInfoDictionaryKey:@"NSAppTransportSecurity"] == nil);
                
                if (updatingMainBundle) {
                    // The only way we'll know for sure if there is an issue is if the main bundle is the same as the one we're updating
                    // We don't want to generate false positives..
                    foundATSMainBundleIssue = foundATSIssue;
                }
            }
            
            if (foundATSPersistentIssue || foundATSMainBundleIssue) {
                // Just log a warning. Don't outright fail in case we are wrong (eg: app is linked on an old SDK where ATS doesn't take effect)
                SULog(SULogLevelDefault, @"The feed URL (%@) may need to change to use HTTPS.\nFor more information: https://sparkle-project.org/documentation/app-transport-security", [feedURL absoluteString]);
                
                _loggedATSWarning = YES;
            }
        }
    }
    
    SUPublicKeys *publicKeys = _host.publicKeys;
    BOOL hasAnyPublicKey = publicKeys.hasAnyKeys;
    if (!hasAnyPublicKey) {
        // If we failed to retrieve a DSA key but the bundle specifies a path to one, we should consider this a configuration failure
        NSString *publicDSAKeyFileKey = [_host publicDSAKeyFileKey];
        if (publicDSAKeyFileKey != nil) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUNoPublicDSAFoundError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The DSA public key '%@' could not be found for %@.", publicDSAKeyFileKey, hostName] }];
            }
            return NO;
        }
    }
    
    // Don't allow invalid EdDSA public keys
    if (publicKeys.ed25519PubKeyStatus == SUSigningInputStatusInvalid) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUNoPublicDSAFoundError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The EdDSA public key is not valid for %@.", hostName] }];
        }
        return NO;
    }

    if (!hasAnyPublicKey) {
        if ((feedURL != nil && !servingOverHttps) || ![SUCodeSigningVerifier bundleAtURLIsCodeSigned:[[self hostBundle] bundleURL]]) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUNoPublicDSAFoundError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"For security reasons, updates need to be signed with an EdDSA key for %@. See Sparkle's documentation for more information.", hostName] }];
            }
            return NO;
        } else {
            if (updatingMainBundle && !_loggedNoSecureKeyWarning) {
                SULog(SULogLevelError, @"Error: Serving updates without an EdDSA key and only using Apple Code Signing is deprecated and may be unsupported in a future release. Visit Sparkle's documentation for more information: https://sparkle-project.org/documentation/#3-segue-for-security-concerns");
                
                _loggedNoSecureKeyWarning = YES;
            }
        }
    } else if (publicKeys.ed25519PubKey == nil) {
        // No EdDSA key is available, so app must be using DSA
        if (updatingMainBundle) {
            if (error != NULL) {
                *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUNoPublicDSAFoundError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"For security reasons, updates need to be signed with an EdDSA key for %@. Please migrate to using EdDSA (ed25519). Visit Sparkle's documentation for migration information: https://sparkle-project.org/documentation/#3-segue-for-security-concerns.", hostName] }];
            }
            return NO;
        }
    }
    
    return YES;
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], [_host bundlePath]]; }

- (void)startUpdateCycle __attribute__((objc_direct))
{
    BOOL shouldPrompt = NO;
    BOOL hasLaunchedBefore = [_host boolForUserDefaultsKey:SUHasLaunchedBeforeKey];

    id<SPUUpdaterDelegate> delegate = _delegate;
    
    // If the user has been asked about automatic checks, don't bother prompting
    // When the user answers to the permission prompt, this will be set to either @YES or @NO instead of nil
    if ([_host objectForUserDefaultsKey:SUEnableAutomaticChecksKey] != nil) {
        shouldPrompt = NO;
    }
    // Does the delegate want to take care of the logic for when we should ask permission to update?
    else if ([delegate respondsToSelector:@selector((updaterShouldPromptForPermissionToCheckForUpdates:))]) {
        shouldPrompt = [delegate updaterShouldPromptForPermissionToCheckForUpdates:self];
    }
    // Has the user been asked already? And don't ask if the host has a default value set in its Info.plist.
    else if ([_host objectForKey:SUEnableAutomaticChecksKey] == nil) {
        // We wait until the second launch of the updater for this host bundle, unless explicitly overridden via SUPromptUserOnFirstLaunchKey.
        shouldPrompt = [_host objectForKey:SUPromptUserOnFirstLaunchKey] || hasLaunchedBefore;
    }
    
    if (!hasLaunchedBefore) {
        [_host setBool:YES forUserDefaultsKey:SUHasLaunchedBeforeKey];
    }

    if (shouldPrompt) {
        NSArray<NSDictionary<NSString *, NSString *> *> *profileInfo = self.systemProfileArray;
        // Always say we're sending the system profile here so that the delegate displays the parameters it would send.
        if ([delegate respondsToSelector:@selector((feedParametersForUpdater:sendingSystemProfile:))]) {
            NSArray *feedParameters = [delegate feedParametersForUpdater:self sendingSystemProfile:YES];
            if (feedParameters != nil) {
                profileInfo = [profileInfo arrayByAddingObjectsFromArray:feedParameters];
            }
        }
        
        SPUUpdatePermissionRequest *updatePermissionRequest = [[SPUUpdatePermissionRequest alloc] initWithSystemProfile:profileInfo];
        
        _showingPermissionRequest = YES;
        [self setSessionInProgress:YES];
        [self setCanCheckForUpdates:YES];
        
        __weak __typeof__(self) weakSelf = self;
        [_userDriver showUpdatePermissionRequest:updatePermissionRequest reply:^(SUUpdatePermissionResponse *response) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __typeof__(self) strongSelf = weakSelf;
                if (strongSelf != nil) {
                    [strongSelf setSessionInProgress:NO];
                    strongSelf->_showingPermissionRequest = NO;
                    
                    [strongSelf updatePermissionRequestFinishedWithResponse:response];
                    // Schedule checks, but make sure we ignore the delayed call from KVO
                    [strongSelf resetUpdateCycle];
                }
            });
        }];
        
        // We start the update checks and register as observer for changes after the prompt finishes
    } else {
        // We check if the user's said they want updates, or they haven't said anything, and the default is set to checking.
        [self scheduleNextUpdateCheckFiringImmediately:NO usingCurrentDate:YES];
    }
}

- (void)updatePermissionRequestFinishedWithResponse:(SUUpdatePermissionResponse *)response __attribute__((objc_direct))
{
    [self setSendsSystemProfile:response.sendSystemProfile];
    [self setAutomaticallyChecksForUpdates:response.automaticUpdateChecks];
    
    NSNumber *automaticUpdateDownloading = response.automaticUpdateDownloading;
    if (automaticUpdateDownloading != nil) {
        [self setAutomaticallyDownloadsUpdates:automaticUpdateDownloading.boolValue];
    }
}

- (NSDate *)lastUpdateCheckDate
{
    if (_updateLastCheckedDate == nil)
    {
        _updateLastCheckedDate = [_host objectForUserDefaultsKey:SULastCheckTimeKey];
    }
    
    return _updateLastCheckedDate;
}

- (void)updateLastUpdateCheckDate __attribute__((objc_direct))
{
    [self willChangeValueForKey:NSStringFromSelector(@selector((lastUpdateCheckDate)))];
    // We use an intermediate property for last update check date due to https://github.com/sparkle-project/Sparkle/pull/1135
    _updateLastCheckedDate = [NSDate date];
    [_host setObject:_updateLastCheckedDate forUserDefaultsKey:SULastCheckTimeKey];
    [self didChangeValueForKey:NSStringFromSelector(@selector((lastUpdateCheckDate)))];
}

// Note this method is never called when sessionInProgress is YES
- (void)scheduleNextUpdateCheckFiringImmediately:(BOOL)firingImmediately usingCurrentDate:(BOOL)usingCurrentDate __attribute__((objc_direct))
{
    [_updaterTimer invalidate];
    
    id<SPUUpdaterDelegate> delegate = _delegate;
    if (!firingImmediately && ![self automaticallyChecksForUpdates]) {
        if ([delegate respondsToSelector:@selector(updaterWillNotScheduleUpdateCheck:)]) {
            [delegate updaterWillNotScheduleUpdateCheck:self];
        }
        return;
    }
    
    if (firingImmediately) {
        [self checkForUpdatesInBackground];
    } else {
        // This may not return the same update check interval as the developer has configured
        // Notably it may differ when we have an update that has been already downloaded and needs to resume,
        // as well as if that update is marked critical or not
        void (^retrieveNextUpdateCheckInterval)(void (^)(NSTimeInterval)) = ^(void (^completionHandler)(NSTimeInterval)) {
            NSString *hostBundleIdentifier = self->_host.bundle.bundleIdentifier;
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
        };
        
        self.canCheckForUpdates = NO;
        self.sessionInProgress = YES;
        
        retrieveNextUpdateCheckInterval(^(NSTimeInterval updateCheckInterval) {
            [self setCanCheckForUpdates:YES];
            [self setSessionInProgress:NO];
            
            // This callback is asynchronous, so the timer may be set. Invalidate to make sure it isn't.
            [self->_updaterTimer invalidate];
            
            NSTimeInterval intervalSinceCheck;
            if (usingCurrentDate) {
                // How long has it been since last we checked for an update?
                NSDate *lastCheckDate = [self lastUpdateCheckDate];
                if (!lastCheckDate) { lastCheckDate = [NSDate distantPast]; }
                intervalSinceCheck = [[NSDate date] timeIntervalSinceDate:lastCheckDate];
                if (intervalSinceCheck < 0) {
                    // Last update check date is in the future and bogus, so reset it to current date
                    [self updateLastUpdateCheckDate];
                    
                    intervalSinceCheck = 0;
                }
            } else {
                intervalSinceCheck = 0;
            }
            
            // Now we want to figure out how long until we check again.
            if (updateCheckInterval < SUMinimumUpdateCheckInterval)
                updateCheckInterval = SUMinimumUpdateCheckInterval;
            if (intervalSinceCheck < updateCheckInterval) {
                NSTimeInterval delayUntilCheck = (updateCheckInterval - intervalSinceCheck); // It hasn't been long enough.
                if ([delegate respondsToSelector:@selector(updater:willScheduleUpdateCheckAfterDelay:)]) {
                    [delegate updater:self willScheduleUpdateCheckAfterDelay:delayUntilCheck];
                }
                
                if ([self->_userDriver respondsToSelector:@selector(logGentleScheduledUpdateReminderWarningIfNeeded)]) {
                    [(id<SPUGentleUserDriverReminders>)self->_userDriver logGentleScheduledUpdateReminderWarningIfNeeded];
                }
                
                [self->_updaterTimer startAndFireAfterDelay:delayUntilCheck];
            } else {
                // We're overdue! Run one now.
                [self checkForUpdatesInBackground];
            }
        });
    }
}

- (void)updaterTimerDidFire
{
    [self checkForUpdatesInBackground];
}

- (void)checkForUpdatesInBackground
{
    if (!_startedUpdater) {
        SULog(SULogLevelError, @"Error: checkForUpdatesInBackground - updater hasn't been started yet. Please call -startUpdater: first");
        return;
    }
    
    if (_sessionInProgress) {
        SULog(SULogLevelError, @"Error: -checkForUpdatesInBackground called but .sessionInProgress == YES");
        return;
    }
    
    [self setSessionInProgress:YES];
    [self setCanCheckForUpdates:NO];
    
    // We don't want the probe check to act on the driver if the updater is going near death
    __weak __typeof__(self) weakSelf = self;
    
    NSString *hostBundleIdentifier = _host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    [SPUProbeInstallStatus probeInstallerInProgressForHostBundleIdentifier:hostBundleIdentifier completion:^(BOOL installerIsRunning) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __typeof__(self) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            
            id<SPUUpdaterDelegate> delegate = strongSelf->_delegate;
            id <SPUUpdateDriver> updateDriver;
            if (!installerIsRunning && [strongSelf automaticallyDownloadsUpdates] && strongSelf->_resumableUpdate == nil) {
                updateDriver =
                [[SPUAutomaticUpdateDriver alloc]
                 initWithHost:strongSelf->_host
                 applicationBundle:strongSelf->_applicationBundle
                 updater:strongSelf
                 userDriver:strongSelf->_userDriver
                 updaterDelegate:delegate];
            } else {
                updateDriver =
                [[SPUScheduledUpdateDriver alloc]
                 initWithHost:strongSelf->_host
                 applicationBundle:strongSelf->_applicationBundle
                 updater:strongSelf
                 userDriver:strongSelf->_userDriver
                 updaterDelegate:delegate];
            }
            
            [strongSelf checkForUpdatesWithDriver:updateDriver updateCheck:SPUUpdateCheckUpdatesInBackground installerInProgress:installerIsRunning];
        });
    }];
}

- (void)checkForUpdates
{
    if (_showingPermissionRequest || _driver.showingUpdate) {
        if ([_userDriver respondsToSelector:@selector(showUpdateInFocus)]) {
            [_userDriver showUpdateInFocus];
        }
        return;
    }
    
    if (!_startedUpdater) {
        SULog(SULogLevelError, @"Error: checkForUpdates - updater hasn't been started yet. Please call -startUpdater: first");
        return;
    }
    
    if (_sessionInProgress) {
        SULog(SULogLevelError, @"Error: -checkForUpdates called but .sessionInProgress == YES");
        return;
    }
    
    if (_driver != nil) {
        return;
    }
    
    [self setSessionInProgress:YES];
    [self setCanCheckForUpdates:NO];
    
    id <SPUUpdateDriver> theUpdateDriver = [[SPUUserInitiatedUpdateDriver alloc] initWithHost:_host applicationBundle:_applicationBundle updater:self userDriver:_userDriver updaterDelegate:_delegate];
    
    NSString *bundleIdentifier = _host.bundle.bundleIdentifier;
    assert(bundleIdentifier != nil);
    
    __weak __typeof__(self) weakSelf = self;
    [SPUProbeInstallStatus probeInstallerInProgressForHostBundleIdentifier:bundleIdentifier completion:^(BOOL installerInProgress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __typeof__(self) strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf checkForUpdatesWithDriver:theUpdateDriver updateCheck:SPUUpdateCheckUpdates installerInProgress:installerInProgress];
            }
        });
    }];
}

- (void)checkForUpdateInformation
{
    __weak __typeof__(self) weakSelf = self;
    if (!_startedUpdater) {
        SULog(SULogLevelError, @"Error: checkForUpdateInformation - updater hasn't been started yet. Please call -startUpdater: first");
        return;
    }
    
    if (_sessionInProgress) {
        SULog(SULogLevelError, @"Error: -checkForUpdateInformation called but .sessionInProgress == YES");
        return;
    }
    
    [self setSessionInProgress:YES];
    [self setCanCheckForUpdates:NO];
    
    NSString *bundleIdentifier = _host.bundle.bundleIdentifier;
    assert(bundleIdentifier != nil);
    [SPUProbeInstallStatus probeInstallerInProgressForHostBundleIdentifier:bundleIdentifier completion:^(BOOL installerInProgress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __typeof__(self) strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf checkForUpdatesWithDriver:[[SPUProbingUpdateDriver alloc] initWithHost:strongSelf->_host updater:strongSelf updaterDelegate:strongSelf->_delegate] updateCheck:SPUUpdateCheckUpdateInformation installerInProgress:installerInProgress];
            }
        });
    }];
}

- (void)checkForUpdatesWithDriver:(id <SPUUpdateDriver> )d updateCheck:(SPUUpdateCheck)updateCheck installerInProgress:(BOOL)installerInProgress __attribute__((objc_direct))
{
    assert(_driver == nil);
    if (_driver != nil) {
        return;
    }
    
    [_updaterTimer invalidate];

    [self updateLastUpdateCheckDate];

    _driver = d;
    assert(_driver != nil);
    
    void (^notifyDelegateOfDriverCompletion)(NSError * _Nullable, BOOL) = ^(NSError * _Nullable error, BOOL shouldShowUpdateImmediately) {
        id<SPUUpdaterDelegate> delegate = self->_delegate;
        
        if (error != nil) {
            if (error.code != SUNoUpdateError && error.code != SUInstallationCanceledError && error.code != SUInstallationAuthorizeLaterError) { // Let's not bother logging this.
                SULogError(error);
            }
            
            // Notify host app that update driver has aborted if a non-recoverable error occurs
            if (error.code != SUInstallationAuthorizeLaterError && [delegate respondsToSelector:@selector((updater:didAbortWithError:))]) {
                [delegate updater:self didAbortWithError:(NSError * _Nonnull)error];
            }
        }
        
        // Notify host app that update driver has finished
        // As long as we're not going to immmediately kick off a new check
        if (!shouldShowUpdateImmediately && [delegate respondsToSelector:@selector((updater:didFinishUpdateCycleForUpdateCheck:error:))]) {
            [delegate updater:self didFinishUpdateCycleForUpdateCheck:updateCheck error:error];
        }
    };
    
    void (^abortUpdateDriver)(NSError  * _Nullable , BOOL) = ^(NSError * _Nullable abortError, BOOL shouldScheduleNextUpdateCheck) {
        __weak __typeof__(self) weakSelf = self;
        [self->_driver setCompletionHandler:^(BOOL __unused shouldShowUpdateImmediately, id<SPUResumableUpdate>  _Nullable __unused resumableUpdate, NSError * _Nullable error) {
            __typeof__(self) strongSelf = weakSelf;
            if (strongSelf != nil) {
                strongSelf->_driver = nil;
                
                [strongSelf updateLastUpdateCheckDate];
                
                strongSelf.sessionInProgress = NO;
                strongSelf.canCheckForUpdates = YES;
                
                notifyDelegateOfDriverCompletion(error, NO);
                
                // Ensure the delegate doesn't start a new session when being notified of the previous one ending
                if (!strongSelf->_sessionInProgress) {
                    if (shouldScheduleNextUpdateCheck) {
                        [strongSelf scheduleNextUpdateCheckFiringImmediately:NO usingCurrentDate:NO];
                    } else {
                        SULog(SULogLevelDefault, @"Disabling scheduled updates..");
                    }
                }
            }
        }];
        
        [self->_driver abortUpdateWithError:abortError];
    };
    
    // Check if the delegate wants to defer checking for updates
    id<SPUUpdaterDelegate> delegate = _delegate;
    NSError *mayCheckForUpdatesError = nil;
    if (
        ([delegate respondsToSelector:@selector(updater:mayPerformUpdateCheck:error:)] && ![delegate updater:self mayPerformUpdateCheck:updateCheck error:&mayCheckForUpdatesError]) ||
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        ([delegate respondsToSelector:@selector((updaterMayCheckForUpdates:))] && ![delegate updaterMayCheckForUpdates:self]))
#pragma clang diagnostic pop
    {
        abortUpdateDriver(mayCheckForUpdatesError, YES);
        return;
    }

    // Because an application can change the configuration (eg: the feed url) at any point, we should always check if it's valid
    // We will not schedule a next update check if the bundle is misconfigured
    NSError *configurationError = nil;
    if (![self checkIfConfiguredProperlyAndRequireFeedURL:YES validateXPCServices:NO error:&configurationError]) {
        SULog(SULogLevelError, @"Sparkle configuration error (%ld): %@", (long)configurationError.code, configurationError.localizedDescription);
        
        abortUpdateDriver(configurationError, NO);
        return;
    }
    
    // Run our update driver and schedule next update check on its completion
    __weak __typeof__(self) weakSelf = self;
    [_driver setCompletionHandler:^(BOOL shouldShowUpdateImmediately, id<SPUResumableUpdate>  _Nullable resumableUpdate, NSError * _Nullable error) {
        __typeof__(self) strongSelf = weakSelf;
        if (strongSelf != nil) {
            strongSelf->_resumableUpdate = resumableUpdate;
            strongSelf->_driver = nil;
            
            [strongSelf updateLastUpdateCheckDate];
            
            [strongSelf setSessionInProgress:NO];
            [strongSelf setCanCheckForUpdates:YES];
            
            notifyDelegateOfDriverCompletion(error, shouldShowUpdateImmediately);
            
            // Ensure the delegate doesn't start a new session when being notified of the previous one ending
            if (!strongSelf->_sessionInProgress) {
                [strongSelf scheduleNextUpdateCheckFiringImmediately:shouldShowUpdateImmediately usingCurrentDate:NO];
            }
        }
    }];
    
    [_driver setUpdateShownHandler:^{
        weakSelf.canCheckForUpdates = YES;
    }];
    
    [_driver setUpdateWillInstallHandler:^{
        [weakSelf updateLastUpdateCheckDate];
    }];
    
    if (installerInProgress) {
        // Resume an update that has already begun installing in the background
        [_driver resumeInstallingUpdate];
    } else if (_resumableUpdate != nil) {
        // Resume an update or info that has already been downloaded
        [_driver resumeUpdate:(id<SPUResumableUpdate> _Nonnull)_resumableUpdate];
    } else {
        // Check that the parameterized feed URL is valid
        NSURL *theFeedURL = [self parameterizedFeedURL];
        if (theFeedURL == nil) {
            // I think this is really unlikely to occur but better be safe
            // We will not schedule a next update check if the feed URL cannot be formed
            SULog(SULogLevelError, @"Error: failed to retrieve feed URL for bundle");
            
            abortUpdateDriver([NSError errorWithDomain:SUSparkleErrorDomain code:SUInvalidFeedURLError userInfo:@{ NSLocalizedDescriptionKey: @"Sparkle cannot form a valid feed URL." }], NO);
        } else {
            // Check for new updates
            [_driver checkForUpdatesAtAppcastURL:theFeedURL withUserAgent:_userAgentString httpHeaders:_httpHeaders];
        }
    }
}

- (void)cancelNextUpdateCycle
{
    [_updaterCycle cancelNextUpdateCycle];
}

- (void)resetUpdateCycle
{
    if (!_startedUpdater) {
        SULog(SULogLevelError, @"Error: resetUpdateCycle - updater hasn't been started yet. Please call -startUpdater: first");
        return; // not even ready yet
    }
    
    // Note this resets the opportune time when user grants Sparkle permission to check for updates
    // and when the user changes preferences on automatically checking for updates or the update time check interval
    if ([_userDriver respondsToSelector:@selector(resetTimeSinceOpportuneUpdateNotice)]) {
        [(id<SPUGentleUserDriverReminders>)_userDriver resetTimeSinceOpportuneUpdateNotice];
    }
    
    if (!_sessionInProgress) {
        [self cancelNextUpdateCycle];
        [self scheduleNextUpdateCheckFiringImmediately:NO usingCurrentDate:YES];
    }
}

- (void)resetUpdateCycleAfterShortDelay
{
    [self cancelNextUpdateCycle];
    [_updaterCycle resetUpdateCycleAfterDelay];
}

- (void)setAutomaticallyChecksForUpdates:(BOOL)automaticallyCheckForUpdates
{
    [_host setBool:automaticallyCheckForUpdates forUserDefaultsKey:SUEnableAutomaticChecksKey];
    // Hack to support backwards compatibility with older Sparkle versions, which supported
    // disabling updates by setting the check interval to 0.
    if (automaticallyCheckForUpdates && (NSInteger)[self updateCheckInterval] == 0) {
        [self setUpdateCheckInterval:SUDefaultUpdateCheckInterval];
    }
    
    if (_startedUpdater) {
        // Provide a small delay in case multiple preferences are being updated simultaneously.
        [self resetUpdateCycleAfterShortDelay];
    }
}

- (BOOL)automaticallyChecksForUpdates
{
    return [_updaterSettings automaticallyChecksForUpdates];
}

- (void)setAutomaticallyDownloadsUpdates:(BOOL)automaticallyUpdates
{
    [_host setBool:automaticallyUpdates forUserDefaultsKey:SUAutomaticallyUpdateKey];
}

- (BOOL)automaticallyDownloadsUpdates
{
    return [_updaterSettings allowsAutomaticUpdates] && [_updaterSettings automaticallyDownloadsUpdates];
}

- (void)setFeedURL:(NSURL * _Nullable)feedURL
{
    if (![NSThread isMainThread]) {
        SULog(SULogLevelError, @"Error: SPUUpdater -setFeedURL: must be called on the main thread. The call from a background thread was ignored.");
        return;
    }

    // When feedURL is nil, -absoluteString will return nil and will remove the user default key
    [_host setObject:[feedURL absoluteString] forUserDefaultsKey:SUFeedURLKey];
}

- (NSURL * _Nullable)retrieveFeedURL:(NSError * __autoreleasing *)error __attribute__((objc_direct))
{
    NSString *hostName = _host.name;
    
    if (![NSThread isMainThread]) {
        SULog(SULogLevelError, @"Error: SPUUpdater -retrieveFeedURL:error: must be called on the main thread.");
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUIncorrectAPIUsageError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"SUUpdater -retriveFeedURL:error: must be called on the main thread for %@", hostName]}];
        }
        return nil;
    }
    
    // A value in the user defaults overrides one in the Info.plist (so preferences panels can be created wherein users choose between beta / release feeds).
    NSString *appcastString = [_host objectForKey:SUFeedURLKey];
    id<SPUUpdaterDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector((feedURLStringForUpdater:))]) {
        NSString *delegateAppcastString = [delegate feedURLStringForUpdater:self];
        if (delegateAppcastString != nil) {
            appcastString = delegateAppcastString;
        }
    }
    
    if (!appcastString) { // Can't find an appcast string!
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInvalidFeedURLError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"You must specify the URL of the appcast as the %@ key in either the Info.plist, or with -feedURLStringForUpdater: delegate method, or by the user defaults of %@!", SUFeedURLKey, hostName] }];
        }
        return nil;
    }
    
    NSCharacterSet *quoteSet = [NSCharacterSet characterSetWithCharactersInString:@"\"\'"]; // Some feed publishers add quotes; strip 'em.
    NSString *castUrlStr = [appcastString stringByTrimmingCharactersInSet:quoteSet];
    if (castUrlStr == nil || [castUrlStr length] == 0) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInvalidFeedURLError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Appcast feed (%@) after trimming it of quotes is empty for %@!", appcastString, hostName] }];
        }
        return nil;
    }
    
    NSURL *feedURL = [NSURL URLWithString:castUrlStr];
    if (feedURL == nil) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUInvalidFeedURLError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Appcast feed (%@) after converting it to a URL is invalid for %@!", appcastString, hostName] }];
        }
        return nil;
    }
    
    return feedURL;
}

// A client may call this method but do not invoke this method ourselves because it's unsafe
- (NSURL * _Nullable)feedURL
{
    NSError *feedError = nil;
    NSURL *feedURL = [self retrieveFeedURL:&feedError];
    if (feedURL == nil) {
        SULog(SULogLevelError, @"Feed Error (%ld): %@", feedError.code, feedError.localizedDescription);
        return nil;
    }
    return feedURL;
}

- (void)setSendsSystemProfile:(BOOL)sendsSystemProfile
{
    [_host setBool:sendsSystemProfile forUserDefaultsKey:SUSendProfileInfoKey];
}

- (BOOL)sendsSystemProfile
{
    return [_updaterSettings sendsSystemProfile];
}

static NSString *escapeURLComponent(NSString *str) {
    NSString *escapedString = [str stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.URLQueryAllowedCharacterSet];
    
    return [[[escapedString stringByReplacingOccurrencesOfString:@"=" withString:@"%3d"] stringByReplacingOccurrencesOfString:@"&" withString:@"%26"] stringByReplacingOccurrencesOfString:@"+" withString:@"%2b"];
}

// Precondition: The feed URL should be valid
- (NSURL * _Nullable)parameterizedFeedURL __attribute__((objc_direct))
{
    NSURL *baseFeedURL = [self retrieveFeedURL:NULL];
    if (baseFeedURL == nil) {
        SULog(SULogLevelError, @"Unexpected error: base feed URL is invalid during -parameterizedFeedURL");
        return nil;
    }
    
    // Determine all the parameters we're attaching to the base feed URL.
    BOOL sendingSystemProfile = [self sendsSystemProfile];

    // Let's only send the system profiling information once per week at most, so we normalize daily-checkers vs. biweekly-checkers and the such.
    NSDate *lastSubmitDate = [_host objectForUserDefaultsKey:SULastProfileSubmitDateKey];
    if (!lastSubmitDate) {
        lastSubmitDate = [NSDate distantPast];
    }
    const NSTimeInterval oneWeek = 60 * 60 * 24 * 7;
    sendingSystemProfile &= (-[lastSubmitDate timeIntervalSinceNow] >= oneWeek);

    id<SPUUpdaterDelegate> delegate = _delegate;
    NSArray<NSDictionary<NSString *, NSString *> *> *parameters = @[];
    if ([delegate respondsToSelector:@selector((feedParametersForUpdater:sendingSystemProfile:))]) {
        NSArray *feedParameters = [delegate feedParametersForUpdater:self sendingSystemProfile:sendingSystemProfile];
        if (feedParameters != nil) {
            parameters = [parameters arrayByAddingObjectsFromArray:feedParameters];
        }
    }
	if (sendingSystemProfile)
	{
        parameters = [parameters arrayByAddingObjectsFromArray:[self systemProfileArray]];
        [_host setObject:[NSDate date] forUserDefaultsKey:SULastProfileSubmitDateKey];
    }
	if ([parameters count] == 0) { return baseFeedURL; }

    // Build up the parameterized URL.
    NSMutableArray *parameterStrings = [NSMutableArray array];
    for (NSDictionary<NSString *, NSString *> *currentProfileInfo in parameters) {
        [parameterStrings addObject:[NSString stringWithFormat:@"%@=%@", escapeURLComponent([currentProfileInfo objectForKey:@"key"]), escapeURLComponent([currentProfileInfo objectForKey:@"value"])]];
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

- (NSArray<NSDictionary<NSString *, NSString *> *> *)systemProfileArray {
    id<SPUUpdaterDelegate> delegate = _delegate;
    NSArray *systemProfile = [SUSystemProfiler systemProfileArrayForHost:_host];
    if ([delegate respondsToSelector:@selector(allowedSystemProfileKeysForUpdater:)]) {
        NSArray * allowedKeys = [delegate allowedSystemProfileKeysForUpdater:self];
        if (allowedKeys != nil) {
            NSMutableArray *filteredProfile = [NSMutableArray array];
            for (NSDictionary *profileElement in systemProfile) {
                NSString *key = [profileElement objectForKey:@"key"];
                if (key && [allowedKeys containsObject:key]) {
                    [filteredProfile addObject:profileElement];
                }
            }
            systemProfile = [filteredProfile copy];
        }
    }
    return systemProfile;
}

- (void)setUpdateCheckInterval:(NSTimeInterval)updateCheckInterval
{
    [_host setObject:@(updateCheckInterval) forUserDefaultsKey:SUScheduledCheckIntervalKey];
    if ((NSInteger)updateCheckInterval == 0) { // For compatibility with 1.1's settings.
        [self setAutomaticallyChecksForUpdates:NO];
    }
    
    if (_startedUpdater) {
        // Provide a small delay in case multiple preferences are being updated simultaneously.
        [self resetUpdateCycleAfterShortDelay];
    }
}

- (NSTimeInterval)updateCheckInterval
{
    return [_updaterSettings updateCheckInterval];
}

- (void)dealloc
{
    // Stop checking for updates
    [self cancelNextUpdateCycle];
    [_updaterTimer invalidate];
    
    // Abort any on-going updates
    // A driver could be retained by another object (eg: a timer),
    // so not aborting could mean it stays alive longer than we'd want
    [_driver abortUpdate];
    _driver = nil;
}

- (NSBundle *)hostBundle
{
    return _host.bundle;
}

@end
