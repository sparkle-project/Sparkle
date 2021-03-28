//
//  SUUpdater.m
//  Sparkle
//
//  Created by Andy Matuschak on 1/4/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUUpdater.h"
#import "SPUUpdater.h"
#import "SPUStandardUserDriver.h"
#import "SPUStandardUserDriverDelegate.h"
#import "SPUUpdaterDelegate.h"
#import "SULog.h"

@interface SUUpdater () <SPUUpdaterDelegate, SPUStandardUserDriverDelegate>

@property (nonatomic, readonly) SPUUpdater *updater;
@property (nonatomic, readonly) SPUStandardUserDriver *userDriver;

@property (nonatomic, copy) void(^postponedInstallHandler)(void);
@property (nonatomic, copy) void(^silentInstallHandler)(void);

@property (nonatomic) BOOL loggedInstallUpdatesIfAvailableWarning;

@end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
@implementation SUUpdater
#pragma clang diagnostic pop

@synthesize updater = _updater;
@synthesize delegate = _delegate;
@synthesize userDriver = _userDriver;
@synthesize postponedInstallHandler = _postponedInstallHandler;
@synthesize silentInstallHandler = _silentInstallHandler;
@synthesize decryptionPassword = _decryptionPassword;
@synthesize loggedInstallUpdatesIfAvailableWarning = _loggedInstallUpdatesIfAvailableWarning;

static NSMutableDictionary *sharedUpdaters = nil;

+ (SUUpdater *)sharedUpdater
{
    return [self updaterForBundle:[NSBundle mainBundle]];
}

// SUUpdater has a singleton for each bundle. We use the fact that NSBundle instances are also singletons, so we can use them as keys. If you don't trust that you can also use the identifier as key
+ (SUUpdater *)updaterForBundle:(NSBundle *)bundle
{
    if (bundle == nil) bundle = [NSBundle mainBundle];
    id updater = [sharedUpdaters objectForKey:[NSValue valueWithNonretainedObject:bundle]];
    if (updater == nil) {
        updater = [(SUUpdater *)[[self class] alloc] initForBundle:bundle];
    }
    return updater;
}

// This is the designated initializer for SUUpdater, important for subclasses
- (instancetype)initForBundle:(NSBundle *)bundle
{
    self = [super init];
    if (bundle == nil) bundle = [NSBundle mainBundle];

    id updater = [sharedUpdaters objectForKey:[NSValue valueWithNonretainedObject:bundle]];
    if (updater)
	{
        self = updater;
	}
	else if (self)
	{
        if (sharedUpdaters == nil) {
            sharedUpdaters = [[NSMutableDictionary alloc] init];
        }
        [sharedUpdaters setObject:self forKey:[NSValue valueWithNonretainedObject:bundle]];
        
        // This bundle may not necessarily be the correct application bundle
        // Unfortunately we won't know the correct application bundle until after the delegate is set
        // See -[SUUpdater _standardUserDriverRequestsPathToRelaunch] and -[SUUpdater _pathToRelaunchForUpdater:] implemented below which resolves this
        _userDriver = [[SPUStandardUserDriver alloc] initWithHostBundle:bundle delegate:self];
        _updater = [[SPUUpdater alloc] initWithHostBundle:bundle applicationBundle:bundle userDriver:_userDriver delegate:self];
        
        NSError *updaterError = nil;
        if (![self.updater startUpdater:&updaterError]) {
            SULog(SULogLevelError, @"Error: Failed to start updater with error: %@", updaterError);
        }
    }
    return self;
}

// This will be used when the updater is instantiated in a nib such as MainMenu
- (instancetype)init
{
    SULog(SULogLevelDefault, @"DEPRECATION: SUUpdater is now deprecated. Please use SPUStandardUpdaterController as a nib instantiated replacement, or SPUUpdater.");
    return [self initForBundle:[NSBundle mainBundle]];
}

- (void)resetUpdateCycle
{
    [self.updater resetUpdateCycle];
}

- (NSBundle *)hostBundle
{
    return self.updater.hostBundle;
}

- (NSBundle *)sparkleBundle
{
    return self.updater.sparkleBundle;
}

- (BOOL)automaticallyChecksForUpdates
{
    return self.updater.automaticallyChecksForUpdates;
}

- (void)setAutomaticallyChecksForUpdates:(BOOL)automaticallyChecksForUpdates
{
    [self.updater setAutomaticallyChecksForUpdates:automaticallyChecksForUpdates];
}

- (NSTimeInterval)updateCheckInterval
{
    return self.updater.updateCheckInterval;
}

- (void)setUpdateCheckInterval:(NSTimeInterval)updateCheckInterval
{
    [self.updater setUpdateCheckInterval:updateCheckInterval];
}

- (NSURL *)feedURL
{
    return self.updater.feedURL;
}

- (void)setFeedURL:(NSURL *)feedURL
{
    [self.updater setFeedURL:feedURL];
}

- (NSString *)userAgentString
{
    return self.updater.userAgentString;
}

- (void)setUserAgentString:(NSString *)userAgentString
{
    [self.updater setUserAgentString:userAgentString];
}

- (NSDictionary *)httpHeaders
{
    return self.updater.httpHeaders;
}

- (void)setHttpHeaders:(NSDictionary *)httpHeaders
{
    [self.updater setHttpHeaders:httpHeaders];
}

- (BOOL)sendsSystemProfile
{
    return self.updater.sendsSystemProfile;
}

- (void)setSendsSystemProfile:(BOOL)sendsSystemProfile
{
    [self.updater setSendsSystemProfile:sendsSystemProfile];
}

- (BOOL)automaticallyDownloadsUpdates
{
    return self.updater.automaticallyDownloadsUpdates;
}

- (void)setAutomaticallyDownloadsUpdates:(BOOL)automaticallyDownloadsUpdates
{
    [self.updater setAutomaticallyDownloadsUpdates:automaticallyDownloadsUpdates];
}

- (IBAction)checkForUpdates:(id)__unused sender
{
    [self.updater checkForUpdates];
}
    
- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(checkForUpdates:)) {
        return self.updater.canCheckForUpdates;
    }
    return YES;
}

- (void)checkForUpdatesInBackground
{
    [self.updater checkForUpdatesInBackground];
}

- (NSDate *)lastUpdateCheckDate
{
    return self.updater.lastUpdateCheckDate;
}

- (void)checkForUpdateInformation
{
    [self.updater checkForUpdateInformation];
}

- (BOOL)updateInProgress
{
    // This is not quite true -- we may be able to check / resume an update if one is in progress
    // But this is a close enough approximation for 1.x updater API
    return !self.updater.canCheckForUpdates;
}

// Not implemented properly at the moment - leaning towards it not be in the future
// because it may be hard to implement properly (without passing a boolean flag everywhere), or
// it would require us to maintain support for an additional class used by a very few people thus far
// For now, just invoke the regular background update process if this is invoked. Could change our minds on this later.
- (void)installUpdatesIfAvailable
{
    if (!self.loggedInstallUpdatesIfAvailableWarning) {
        SULog(SULogLevelError, @"-[%@ installUpdatesIfAvailable] does not function anymore.. Instead a background scheduled update check will be done.", NSStringFromClass([self class]));
        
        self.loggedInstallUpdatesIfAvailableWarning = YES;
        }

    [self checkForUpdatesInBackground];
}

- (void)standardUserDriverWillShowModalAlert
{
    if ([self.delegate respondsToSelector:@selector(updaterWillShowModalAlert:)]) {
        [self.delegate updaterWillShowModalAlert:self];
    }
}

- (void)standardUserDriverDidShowModalAlert
{
    if ([self.delegate respondsToSelector:@selector(updaterDidShowModalAlert:)]) {
        [self.delegate updaterDidShowModalAlert:self];
    }
}

- (_Nullable id <SUVersionDisplay>)standardUserDriverRequestsVersionDisplayer
{
    id <SUVersionDisplay> versionDisplayer = nil;
    if ([self.delegate respondsToSelector:@selector(versionDisplayerForUpdater:)]) {
        versionDisplayer = [self.delegate versionDisplayerForUpdater:self];
    }
    return versionDisplayer;
}

- (BOOL)updaterMayCheckForUpdates:(SPUUpdater *)__unused updater
{
    BOOL updaterMayCheck = YES;
    if ([self.delegate respondsToSelector:@selector(updaterMayCheckForUpdates:)]) {
        updaterMayCheck = [self.delegate updaterMayCheckForUpdates:self];
    }
    return updaterMayCheck;
}

- (NSArray *)feedParametersForUpdater:(SPUUpdater *)__unused updater sendingSystemProfile:(BOOL)sendingProfile
{
    NSArray *feedParameters;
    if ([self.delegate respondsToSelector:@selector(feedParametersForUpdater:sendingSystemProfile:)]) {
        feedParameters = [self.delegate feedParametersForUpdater:self sendingSystemProfile:sendingProfile];
    } else {
        feedParameters = [NSArray array];
    }
    return feedParameters;
}

- (NSString *)feedURLStringForUpdater:(SPUUpdater *)__unused updater
{
    // Be really careful not to call [self feedURL] here. That might lead us into infinite recursion.
    NSString *feedURL = nil;
    if ([self.delegate respondsToSelector:@selector(feedURLStringForUpdater:)]) {
        feedURL = [self.delegate feedURLStringForUpdater:self];
    }
    return feedURL;
}

- (BOOL)updaterShouldPromptForPermissionToCheckForUpdates:(SPUUpdater *)__unused updater
{
    BOOL shouldPrompt = YES;
    if ([self.delegate respondsToSelector:@selector(updater:didFinishLoadingAppcast:)]) {
        shouldPrompt = [self.delegate updaterShouldPromptForPermissionToCheckForUpdates:self];
    }
    return shouldPrompt;
}

- (void)updater:(SPUUpdater *)__unused updater didFinishLoadingAppcast:(SUAppcast *)appcast
{
    if ([self.delegate respondsToSelector:@selector(updater:didFinishLoadingAppcast:)]) {
        [self.delegate updater:self didFinishLoadingAppcast:appcast];
    }
}

- (SUAppcastItem *)bestValidUpdateInAppcast:(SUAppcast *)appcast forUpdater:(SPUUpdater *)__unused updater
{
    SUAppcastItem *bestValidUpdate = nil;
    if ([self.delegate respondsToSelector:@selector(bestValidUpdateInAppcast:forUpdater:)]) {
        bestValidUpdate = [self.delegate bestValidUpdateInAppcast:appcast forUpdater:self];
    }
    return bestValidUpdate;
}

- (void)updater:(SPUUpdater *)__unused updater didFindValidUpdate:(SUAppcastItem *)item
{
    if ([self.delegate respondsToSelector:@selector(updater:didFindValidUpdate:)]) {
        [self.delegate updater:self didFindValidUpdate:item];
    }
}

- (void)updaterDidNotFindUpdate:(SPUUpdater *)__unused updater
{
    if ([self.delegate respondsToSelector:@selector(updaterDidNotFindUpdate:)]) {
        [self.delegate updaterDidNotFindUpdate:self];
    }
}

- (void)updater:(SPUUpdater *)__unused updater userDidSkipThisVersion:(nonnull SUAppcastItem *)item
{
    if ([self.delegate respondsToSelector:@selector(updater:userDidSkipThisVersion:)]) {
        [self.delegate updater:self userDidSkipThisVersion:item];
    }
}

- (void)updater:(SPUUpdater *)__unused updater willDownloadUpdate:(SUAppcastItem *)item withRequest:(NSMutableURLRequest *)request
{
    if ([self.delegate respondsToSelector:@selector(updater:willDownloadUpdate:withRequest:)]) {
        [self.delegate updater:self willDownloadUpdate:item withRequest:request];
    }
}

- (void)updater:(SPUUpdater *)__unused updater didDownloadUpdate:(SUAppcastItem *)item
{
    if ([self.delegate respondsToSelector:@selector(updater:didDownloadUpdate:)]) {
        [self.delegate updater:self didDownloadUpdate:item];
    }
}

- (void)updater:(SPUUpdater *)__unused updater failedToDownloadUpdate:(SUAppcastItem *)item error:(NSError *)error
{
    if ([self.delegate respondsToSelector:@selector(updater:failedToDownloadUpdate:error:)]) {
        [self.delegate updater:self failedToDownloadUpdate:item error:error];
    }
}

- (void)userDidCancelDownload:(SPUUpdater *)__unused updater
{
    if ([self.delegate respondsToSelector:@selector(userDidCancelDownload:)]) {
        [self.delegate userDidCancelDownload:self];
    }
}

- (void)updater:(SPUUpdater *)updater willExtractUpdate:(SUAppcastItem *)item
{
    if ([self.delegate respondsToSelector:@selector(updater:willExtractUpdate:)]) {
        [self.delegate updater:self willExtractUpdate:item];
    }
}

- (void)updater:(SPUUpdater *)updater didExtractUpdate:(SUAppcastItem *)item
{
    if ([self.delegate respondsToSelector:@selector(updater:didExtractUpdate:)]) {
        [self.delegate updater:self didExtractUpdate:item];
    }
}

- (void)updater:(SPUUpdater *)__unused updater willInstallUpdate:(SUAppcastItem *)item
{
    if ([self.delegate respondsToSelector:@selector(updater:willInstallUpdate:)]) {
        [self.delegate updater:self willInstallUpdate:item];
    }
}

- (void)installPostponedUpdate
{
    if (self.postponedInstallHandler != nil) {
        self.postponedInstallHandler();
        self.postponedInstallHandler = nil;
    }
}

- (BOOL)updater:(SPUUpdater *)__unused updater shouldPostponeRelaunchForUpdate:(SUAppcastItem *)item untilInvokingBlock:(void (^)(void))installHandler
{
    BOOL shouldPostponeRelaunch = NO;
    
    if ([self.delegate respondsToSelector:@selector(updater:shouldPostponeRelaunchForUpdate:untilInvoking:)]) {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:@selector(installPostponedUpdate)]];
        
        [invocation setSelector:@selector(installPostponedUpdate)];
        
        // This invocation will retain self, but this instance is kept alive forever by our singleton pattern anyway
        [invocation setTarget:self];

        self.postponedInstallHandler = installHandler;

        shouldPostponeRelaunch = [self.delegate updater:self shouldPostponeRelaunchForUpdate:item untilInvoking:invocation];
    } else if ([self.delegate respondsToSelector:@selector(updater:shouldPostponeRelaunchForUpdate:)]) {
        // This API should really take a block, but not fixing a 1.x mishap now
        shouldPostponeRelaunch = [self.delegate updater:self shouldPostponeRelaunchForUpdate:item];
    }
    
    return shouldPostponeRelaunch;
}

- (BOOL)updaterShouldRelaunchApplication:(SPUUpdater *)__unused updater
{
    BOOL shouldRestart = YES;
    if ([self.delegate respondsToSelector:@selector(updaterShouldRelaunchApplication:)]) {
        shouldRestart = [self.delegate updaterShouldRelaunchApplication:self];
    }
    return shouldRestart;
}

- (void)updaterWillRelaunchApplication:(SPUUpdater *)__unused updater
{
    if ([self.delegate respondsToSelector:@selector(updaterWillRelaunchApplication:)]) {
        [self.delegate updaterWillRelaunchApplication:self];
    }
}

- (id<SUVersionComparison>)versionComparatorForUpdater:(SPUUpdater *)__unused updater
{
    id<SUVersionComparison> versionComparator;
    if ([self.delegate respondsToSelector:@selector(versionComparatorForUpdater:)]) {
        versionComparator = [self.delegate versionComparatorForUpdater:self];
    }
    return versionComparator;
}

// Private SPUUpdater API that allows us to defer providing an application path to relaunch
- (NSString * _Nullable)_pathToRelaunchForUpdater:(SPUUpdater *)__unused updater
{
    NSString *relaunchPath = nil;
    if ([self.delegate respondsToSelector:@selector(pathToRelaunchForUpdater:)]) {
        relaunchPath = [self.delegate pathToRelaunchForUpdater:self];
    }
    return relaunchPath;
}

- (NSString *)decryptionPasswordForUpdater:(SPUUpdater *)__unused updater
{
    return self.decryptionPassword;
}

- (void)finishSilentInstallation
{
    if (self.silentInstallHandler != nil) {
        self.silentInstallHandler();
        self.silentInstallHandler = nil;
    }
}

- (BOOL)updater:(SPUUpdater *)__unused updater willInstallUpdateOnQuit:(SUAppcastItem *)item immediateInstallationBlock:(void (^)(void))immediateInstallHandler
{
    BOOL installationHandledByDelegate = NO;
    
    if ([self.delegate respondsToSelector:@selector((updater:willInstallUpdateOnQuit:immediateInstallationBlock:))]) {
        [self.delegate updater:self willInstallUpdateOnQuit:item immediateInstallationBlock:immediateInstallHandler];
        
        // We have to assume they will handle the installation since they implement this method
        // Not ideal, but this is why this delegate callback is deprecated
        installationHandledByDelegate = YES;
    } else if ([self.delegate respondsToSelector:@selector(updater:willInstallUpdateOnQuit:immediateInstallationInvocation:)]) {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:@selector(finishSilentInstallation)]];
        
        // This invocation will retain self, but this instance is kept alive forever by our singleton pattern anyway
        [invocation setTarget:self];
        
        self.silentInstallHandler = immediateInstallHandler;
        
        [self.delegate updater:self willInstallUpdateOnQuit:item immediateInstallationInvocation:invocation];
        
        // We have to assume they will handle the installation since they implement this method
        // Not ideal, but this is why this delegate callback is deprecated
        installationHandledByDelegate = YES;
    }
    
    return installationHandledByDelegate;
}

- (void)updater:(SPUUpdater *)__unused updater didAbortWithError:(NSError *)error
{
    if ([self.delegate respondsToSelector:@selector(updater:didAbortWithError:)]) {
        [self.delegate updater:self didAbortWithError:error];
    }
}

@end
