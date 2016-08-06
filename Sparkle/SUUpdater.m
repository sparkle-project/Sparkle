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
#import "SULog.h"

@interface SUUpdater () <SPUStandardUserDriverDelegate>

@property (nonatomic, readonly) SPUUpdater *updater;
@property (nonatomic, readonly) SPUStandardUserDriver *userDriver;

@property (nonatomic) BOOL loggedInstallUpdatesIfAvailableWarning;

@end

@interface SPUUpdater (Private)

- (void)setDelegate:(id<SUUpdaterDelegate>)delegate;
- (void)setUpdaterDelegator:(id)delegator;

@end

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
@implementation SUUpdater
#pragma clang diagnostic pop

@synthesize updater = _updater;
@synthesize userDriver = _userDriver;
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
        updater = [[[self class] alloc] initForBundle:bundle];
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
        
        _userDriver = [[SPUStandardUserDriver alloc] initWithHostBundle:bundle delegate:self];
        _updater = [[SPUUpdater alloc] initWithHostBundle:bundle userDriver:_userDriver delegate:nil];
        [_updater setUpdaterDelegator:self];
        
        NSError *updaterError = nil;
        if (![_updater startUpdater:&updaterError]) {
            SULog(@"Error: Falied to start updater with error: %@", updaterError);
            abort();
        }
    }
    return self;
}

// This will be used when the updater is instantiated in a nib such as MainMenu
- (instancetype)init
{
    SULog(@"DEPRECATION: SUUpdater is now deprecated. Please use SPUStandardUpdaterController as a nib instantiated replacement, or SPUUpdater.");
    return [self initForBundle:[NSBundle mainBundle]];
}

- (void)resetUpdateCycle
{
    [self.updater resetUpdateCycle];
}

- (id<SUUpdaterDelegate>)delegate
{
    return self.updater.delegate;
}

- (void)setDelegate:(id<SUUpdaterDelegate>)delegate
{
    // Note: This invokes a private API
    [self.updater setDelegate:delegate];
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
        return self.userDriver.canCheckForUpdates;
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
    return !self.userDriver.canCheckForUpdates;
}

- (void)userDriverWillShowModalAlert
{
    if ([self.updater.delegate respondsToSelector:@selector(updaterWillShowModalAlert:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [self.updater.delegate updaterWillShowModalAlert:self];
#pragma clang diagnostic pop
    }
}

- (void)userDriverDidShowModalAlert
{
    if ([self.updater.delegate respondsToSelector:@selector(updaterDidShowModalAlert:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [self.updater.delegate updaterDidShowModalAlert:self];
#pragma clang diagnostic pop
    }
}

- (_Nullable id <SUVersionDisplay>)userDriverRequestsVersionDisplayer
{
    if ([self.updater.delegate respondsToSelector:@selector(versionDisplayerForUpdater:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        return [self.updater.delegate versionDisplayerForUpdater:self];
#pragma clang diagnostic pop
    }
    return nil;
}

// Not implemented properly at the moment - leaning towards it not be in the future
// because it may be hard to implement properly (without passing a boolean flag everywhere), or
// it would require us to maintain support for an additional class used by a very few people thus far
// For now, just invoke the regular update process if this is invoked. Could change our minds on this later.
- (void)installUpdatesIfAvailable
{
    if (!self.loggedInstallUpdatesIfAvailableWarning) {
        SULog(@"-[%@ installUpdatesIfAvailable] does not function anymore.. Instead a user-initiated update check will be done instead.", NSStringFromClass([self class]));
        
        self.loggedInstallUpdatesIfAvailableWarning = YES;
    }
    
    [self checkForUpdates:nil];
}

// Private API that is used by SUInstallerDriver
- (NSString *)_decryptionPasswordForSparkleUpdater
{
    return self.decryptionPassword;
}

@end
