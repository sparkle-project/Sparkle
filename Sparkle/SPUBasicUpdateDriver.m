//
//  SPUBasicUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUBasicUpdateDriver.h"
#import "SUAppcastDriver.h"
#import "SPUUpdaterDelegate.h"
#import "SUErrors.h"
#import "SULog.h"
#import "SULog+NSError.h"
#import "SULocalizations.h"
#import "SUHost.h"
#import "SUAppcastItem.h"
#import "SPUProbeInstallStatus.h"
#import "SPUInstallationInfo.h"
#import "SPUResumableUpdate.h"


#include "AppKitPrevention.h"

@interface SPUBasicUpdateDriver () <SUAppcastDriverDelegate>

@property (nonatomic, weak, readonly) id<SPUBasicUpdateDriverDelegate> delegate;
@property (nonatomic, readonly) SUAppcastDriver *appcastDriver;
@property (nonatomic, copy) SPUUpdateDriverCompletion completionBlock;

@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, readonly, weak) id updater; // if we didn't have legacy support, I'd remove this..
@property (nullable, nonatomic, readonly, weak) id <SPUUpdaterDelegate>updaterDelegate;

@property (nonatomic) BOOL aborted;

@end

@implementation SPUBasicUpdateDriver

@synthesize host = _host;
@synthesize updater = _updater;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize delegate = _delegate;
@synthesize appcastDriver = _appcastDriver;
@synthesize completionBlock = _completionBlock;
@synthesize aborted = _aborted;

- (instancetype)initWithHost:(SUHost *)host updater:(id)updater updaterDelegate:(id <SPUUpdaterDelegate>)updaterDelegate delegate:(id <SPUBasicUpdateDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _host = host;
        _updater = updater;
        _updaterDelegate = updaterDelegate;
        _delegate = delegate;
        
        _appcastDriver = [[SUAppcastDriver alloc] initWithHost:host updater:updater updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)prepareCheckForUpdatesWithCompletion:(SPUUpdateDriverCompletion)completionBlock
{
    self.completionBlock = completionBlock;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background
{
    if ([self.host isRunningOnReadOnlyVolume]) {
        NSString *hostName = self.host.name;
        if ([self.host isRunningTranslocated]) {
            [self.delegate basicDriverIsRequestingAbortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURunningTranslocated userInfo:@{ NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:SULocalizedString(@"Quit %1$@, move it into your Applications folder, relaunch it from there and try again.", nil), hostName], NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"%1$@ can’t be updated if it’s running from the location it was downloaded to.", nil), hostName], }]];
        } else {
            [self.delegate basicDriverIsRequestingAbortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURunningFromDiskImageError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"%1$@ can't be updated, because it was opened from a read-only or a temporary location.", nil), hostName], NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:SULocalizedString(@"Use Finder to copy %1$@ to the Applications folder, relaunch it from there, and try again.", nil), hostName] }]];
        }
    } else {
        [self.appcastDriver loadAppcastFromURL:appcastURL userAgent:userAgent httpHeaders:httpHeaders inBackground:background];
    }
}

- (void)notifyResumableUpdateItem:(SUAppcastItem *)updateItem secondaryUpdateItem:(SUAppcastItem *)secondaryUpdateItem systemDomain:(NSNumber * _Nullable)systemDomain
{
    if (updateItem == nil) {
        [self.delegate basicDriverIsRequestingAbortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUResumeAppcastError userInfo:@{ NSLocalizedDescriptionKey: SULocalizedString(@"Failed to resume installing update.", nil) }]];
    } else {
        // Kind of lying, but triggering the notification so drivers can know when to stop showing initial fetching progress
        [self notifyFinishLoadingAppcast];
        
        SUAppcastItem *nonNullUpdateItem = updateItem;
        [self notifyFoundValidUpdateWithAppcastItem:nonNullUpdateItem secondaryAppcastItem:secondaryUpdateItem preventsAutoupdate:NO systemDomain:systemDomain];
    }
}

- (void)resumeInstallingUpdateWithCompletion:(SPUUpdateDriverCompletion)completionBlock
{
    self.completionBlock = completionBlock;
    
    NSString *hostBundleIdentifier = self.host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    [SPUProbeInstallStatus probeInstallerUpdateItemForHostBundleIdentifier:hostBundleIdentifier completion:^(SPUInstallationInfo * _Nullable installationInfo) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self notifyResumableUpdateItem:installationInfo.appcastItem secondaryUpdateItem:nil systemDomain:@(installationInfo.systemDomain)];
        });
    }];
}

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate completion:(SPUUpdateDriverCompletion)completionBlock
{
    self.completionBlock = completionBlock;
    
    [self notifyResumableUpdateItem:resumableUpdate.updateItem secondaryUpdateItem:resumableUpdate.secondaryUpdateItem systemDomain:nil];
}

- (void)didFailToFetchAppcastWithError:(NSError *)error
{
    if (!self.aborted) {
        [self.delegate basicDriverIsRequestingAbortUpdateWithError:error];
    }
}

- (void)notifyFinishLoadingAppcast
{
    if ([self.delegate respondsToSelector:@selector(basicDriverDidFinishLoadingAppcast)]) {
        [self.delegate basicDriverDidFinishLoadingAppcast];
    }
}

- (void)didFinishLoadingAppcast:(SUAppcast *)appcast
{
    if (!self.aborted) {
        if ([self.updaterDelegate respondsToSelector:@selector((updater:didFinishLoadingAppcast:))]) {
            [self.updaterDelegate updater:self.updater didFinishLoadingAppcast:appcast];
        }
        
        [self notifyFinishLoadingAppcast];
    }
}

- (void)notifyFoundValidUpdateWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem *)secondaryUpdateItem preventsAutoupdate:(BOOL)preventsAutoupdate systemDomain:(NSNumber * _Nullable)systemDomain
{
    if (!self.aborted) {
        [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFindValidUpdateNotification
                                                            object:self.updater
                                                          userInfo:@{ SUUpdaterAppcastItemNotificationKey: updateItem }];
        
        if ([self.updaterDelegate respondsToSelector:@selector((updater:didFindValidUpdate:))]) {
            [self.updaterDelegate updater:self.updater didFindValidUpdate:updateItem];
        }
        
        [self.delegate basicDriverDidFindUpdateWithAppcastItem:updateItem secondaryAppcastItem:secondaryUpdateItem preventsAutoupdate:preventsAutoupdate systemDomain:systemDomain];
    }
}

- (void)didFindValidUpdateWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem *)secondaryAppcastItem preventsAutoupdate:(BOOL)preventsAutoupdate
{
    [self notifyFoundValidUpdateWithAppcastItem:updateItem secondaryAppcastItem:secondaryAppcastItem preventsAutoupdate:preventsAutoupdate systemDomain:nil];
}

- (void)didNotFindUpdateWithLatestAppcastItem:(nullable SUAppcastItem *)latestAppcastItem hostToLatestAppcastItemComparisonResult:(NSComparisonResult)hostToLatestAppcastItemComparisonResult passesMinOSVersion:(BOOL)passesMinOSVersion passesMaxOSVersion:(BOOL)passesMaxOSVersion
{
    if (!self.aborted) {
        if ([self.updaterDelegate respondsToSelector:@selector((updaterDidNotFindUpdate:))]) {
            [self.updaterDelegate updaterDidNotFindUpdate:self.updater];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidNotFindUpdateNotification object:self.updater];
        
        NSString *localizedDescription;
        NSString *recoverySuggestion;
        NSString *recoveryOption;
        
        if (latestAppcastItem != nil) {
            switch (hostToLatestAppcastItemComparisonResult) {
                case NSOrderedDescending:
                    // This means the user is a 'newer than latest' version. give a slight hint to the user instead of wrongly claiming this version is identical to the latest feed version.
                    localizedDescription = SULocalizedString(@"You're up-to-date!", "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
                    
                    recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.\n(You are currently running version %@.)", nil), [self.host name], latestAppcastItem.displayVersionString, [self.host displayVersion]];
                    break;
                case NSOrderedSame:
                    // No new update is available and we're on the latest
                    localizedDescription = SULocalizedString(@"You're up-to-date!", "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
                    
                    recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.", nil), [self.host name], [self.host displayVersion]];
                    break;
                case NSOrderedAscending:
                    // This means a new update doesn't match the OS requirements
                    if (!passesMinOSVersion) {
                        localizedDescription = SULocalizedString(@"Your macOS version is too old", nil);
                        
                        recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%1$@ %2$@ is available but your macOS version is too old to install it. At least macOS %3$@ is required.", nil), [self.host name], latestAppcastItem.versionString, latestAppcastItem.minimumSystemVersion];
                    } else if (!passesMaxOSVersion) {
                        localizedDescription = SULocalizedString(@"Your macOS version is too new", nil);
                        
                        recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%1$@ %2$@ is available but your macOS version is too new for this update. This update only supports up to macOS %3$@.", nil), [self.host name], latestAppcastItem.versionString, latestAppcastItem.maximumSystemVersion];
                    } else {
                        // We shouldn't realistically get here
                        localizedDescription = SULocalizedString(@"You're up-to-date!", "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
                        
                        recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.", nil), [self.host name], [self.host displayVersion]];
                    }
                    break;
            }
            
            recoveryOption = @"OK";
        } else {
            // When no updates are found in the appcast, or latest appcast item info
            // was not provided (i.e, for a background update check)
            // In the case no info was provided for a background check, the error isn't shown anywhere
            localizedDescription = SULocalizedString(@"Update Error!", nil);
            recoverySuggestion = SULocalizedString(@"No valid update information could be loaded.", nil);
            recoveryOption = SULocalizedString(@"Cancel Update", nil);
        }
        
        NSError *notFoundError =
        [NSError
         errorWithDomain:SUSparkleErrorDomain
         code:SUNoUpdateError
         userInfo:@{
                    NSLocalizedDescriptionKey: localizedDescription,
                    NSLocalizedRecoverySuggestionErrorKey: recoverySuggestion,
                    NSLocalizedRecoveryOptionsErrorKey: @[recoveryOption]
                    }
         ];
        [self.delegate basicDriverIsRequestingAbortUpdateWithError:notFoundError];
    }
}

- (void)abortUpdateAndShowNextUpdateImmediately:(BOOL)shouldShowUpdateImmediately resumableUpdate:(id<SPUResumableUpdate> _Nullable)resumableUpdate error:(nullable NSError *)error
{
    self.aborted = YES;
    
    [self.appcastDriver cleanup:^{
        if (error != nil) {
            if (error.code != SUNoUpdateError && error.code != SUInstallationCanceledError && error.code != SUInstallationAuthorizeLaterError) { // Let's not bother logging this.
                SULogError(error);
            }
            
            // Notify host app that updater has aborted
            if ([self.updaterDelegate respondsToSelector:@selector((updater:didAbortWithError:))]) {
                [self.updaterDelegate updater:self.updater didAbortWithError:(NSError * _Nonnull)error];
            }
        }
        
        if (self.completionBlock != nil) {
            self.completionBlock(shouldShowUpdateImmediately, resumableUpdate);
            self.completionBlock = nil;
        }
    }];
}

@end
