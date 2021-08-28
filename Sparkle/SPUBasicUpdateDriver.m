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
#import "SULocalizations.h"
#import "SUHost.h"
#import "SUAppcastItem.h"
#import "SPUProbeInstallStatus.h"
#import "SPUInstallationInfo.h"
#import "SPUResumableUpdate.h"
#import "SPUAppcastItemState.h"
#import "SUAppcastItem+Private.h"


#include "AppKitPrevention.h"

@interface SPUBasicUpdateDriver () <SUAppcastDriverDelegate>

@property (nonatomic, weak, readonly) id<SPUBasicUpdateDriverDelegate> delegate;
@property (nonatomic, readonly) SUAppcastDriver *appcastDriver;
@property (nonatomic, copy) SPUUpdateDriverCompletion completionBlock;

@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, readonly) SPUUpdateCheck updateCheck;
@property (nonatomic, readonly, weak) id updater; // if we didn't have legacy support, I'd remove this..
@property (nullable, nonatomic, readonly, weak) id <SPUUpdaterDelegate>updaterDelegate;

@property (nonatomic) BOOL aborted;

@end

@implementation SPUBasicUpdateDriver

@synthesize host = _host;
@synthesize updateCheck = _updateCheck;
@synthesize updater = _updater;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize delegate = _delegate;
@synthesize appcastDriver = _appcastDriver;
@synthesize completionBlock = _completionBlock;
@synthesize aborted = _aborted;

- (instancetype)initWithHost:(SUHost *)host updateCheck:(SPUUpdateCheck)updateCheck updater:(id)updater updaterDelegate:(id <SPUUpdaterDelegate>)updaterDelegate delegate:(id <SPUBasicUpdateDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _host = host;
        _updateCheck = updateCheck;
        _updater = updater;
        _updaterDelegate = updaterDelegate;
        _delegate = delegate;
        
        _appcastDriver = [[SUAppcastDriver alloc] initWithHost:host updater:updater updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)setCompletionHandler:(SPUUpdateDriverCompletion)completionBlock
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

- (void)notifyResumableUpdateItem:(SUAppcastItem *)updateItem secondaryUpdateItem:(SUAppcastItem * _Nullable)secondaryUpdateItem systemDomain:(NSNumber * _Nullable)systemDomain
{
    if (updateItem == nil) {
        [self.delegate basicDriverIsRequestingAbortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUResumeAppcastError userInfo:@{ NSLocalizedDescriptionKey: SULocalizedString(@"Failed to resume installing update.", nil) }]];
    } else {
        // Kind of lying, but triggering the notification so drivers can know when to stop showing initial fetching progress
        [self notifyFinishLoadingAppcast];
        
        SUAppcastItem *nonNullUpdateItem = updateItem;
        [self notifyFoundValidUpdateWithAppcastItem:nonNullUpdateItem secondaryAppcastItem:secondaryUpdateItem systemDomain:systemDomain resuming:YES];
    }
}

- (void)resumeInstallingUpdate
{
    NSString *hostBundleIdentifier = self.host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    [SPUProbeInstallStatus probeInstallerUpdateItemForHostBundleIdentifier:hostBundleIdentifier completion:^(SPUInstallationInfo * _Nullable installationInfo) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self notifyResumableUpdateItem:installationInfo.appcastItem secondaryUpdateItem:nil systemDomain:@(installationInfo.systemDomain)];
        });
    }];
}

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate
{
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

- (void)notifyFoundValidUpdateWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryUpdateItem systemDomain:(NSNumber * _Nullable)systemDomain resuming:(BOOL)resuming
{
    if (!self.aborted) {
        // If the update is not being resumed from a prior session, give the delegate a chance to bail
        NSError *shouldNotProceedError = nil;
        if (!resuming && [self.updaterDelegate respondsToSelector:@selector(updater:shouldProceedWithUpdate:updateCheck:error:)] && ![self.updaterDelegate updater:self.updater shouldProceedWithUpdate:updateItem updateCheck:self.updateCheck error:&shouldNotProceedError]) {
            [self.delegate basicDriverIsRequestingAbortUpdateWithError:shouldNotProceedError];
        } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFindValidUpdateNotification
                                                                object:self.updater
                                                              userInfo:@{ SUUpdaterAppcastItemNotificationKey: updateItem }];
            
            if ([self.updaterDelegate respondsToSelector:@selector((updater:didFindValidUpdate:))]) {
                [self.updaterDelegate updater:self.updater didFindValidUpdate:updateItem];
            }
            
            [self.delegate basicDriverDidFindUpdateWithAppcastItem:updateItem secondaryAppcastItem:secondaryUpdateItem systemDomain:systemDomain];
        }
    }
}

- (void)didFindValidUpdateWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryAppcastItem
{
    [self notifyFoundValidUpdateWithAppcastItem:updateItem secondaryAppcastItem:secondaryAppcastItem systemDomain:nil resuming:NO];
}

- (void)didNotFindUpdateWithLatestAppcastItem:(nullable SUAppcastItem *)latestAppcastItem hostToLatestAppcastItemComparisonResult:(NSComparisonResult)hostToLatestAppcastItemComparisonResult background:(BOOL)background
{
    if (!self.aborted) {
        NSString *localizedDescription;
        NSString *recoverySuggestion;
        
        SPUNoUpdateFoundReason reason;
        if (latestAppcastItem != nil) {
            switch (hostToLatestAppcastItemComparisonResult) {
                case NSOrderedDescending:
                    // This means the user is a 'newer than latest' version. give a slight hint to the user instead of wrongly claiming this version is identical to the latest feed version.
                    localizedDescription = SULocalizedString(@"You're up-to-date!", "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
                    
                    recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.\n(You are currently running version %@.)", nil), [self.host name], latestAppcastItem.displayVersionString, [self.host displayVersion]];
                    
                    reason = SPUNoUpdateFoundReasonOnNewerThanLatestVersion;
                    break;
                case NSOrderedSame:
                    // No new update is available and we're on the latest
                    localizedDescription = SULocalizedString(@"You're up-to-date!", "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
                    
                    recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.", nil), [self.host name], [self.host displayVersion]];
                    
                    reason = SPUNoUpdateFoundReasonOnLatestVersion;
                    break;
                case NSOrderedAscending:
                    // A new update is available but cannot be installed
                    
                    if (!latestAppcastItem.minimumOperatingSystemVersionIsOK) {
                        localizedDescription = SULocalizedString(@"Your macOS version is too old", nil);
                        
                        recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%1$@ %2$@ is available but your macOS version is too old to install it. At least macOS %3$@ is required.", nil), [self.host name], latestAppcastItem.versionString, latestAppcastItem.minimumSystemVersion];
                        
                        reason = SPUNoUpdateFoundReasonSystemIsTooOld;
                    } else if (!latestAppcastItem.maximumOperatingSystemVersionIsOK) {
                        localizedDescription = SULocalizedString(@"Your macOS version is too new", nil);
                        
                        recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%1$@ %2$@ is available but your macOS version is too new for this update. This update only supports up to macOS %3$@.", nil), [self.host name], latestAppcastItem.versionString, latestAppcastItem.maximumSystemVersion];
                        
                        reason = SPUNoUpdateFoundReasonSystemIsTooNew;
                    } else {
                        // We shouldn't realistically get here
                        localizedDescription = SULocalizedString(@"You're up-to-date!", "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
                        
                        recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.", nil), [self.host name], [self.host displayVersion]];
                        
                        reason = SPUNoUpdateFoundReasonUnknown;
                    }
                    break;
            }
        } else {
            // When no updates are found in the appcast
            // We will need to assume the user is up to date if the feed doen't have any applicable update items
            // There could be update items on channels the updater is not subscribed to for example. But we can't tell the user about them.
            // There could also only be update items available for other platforms or none at all.
            localizedDescription = SULocalizedString(@"You're up-to-date!", "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
            recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.", nil), [self.host name], [self.host displayVersion]];
            
            reason = SPUNoUpdateFoundReasonOnLatestVersion;
        }
        
        NSString *recoveryOption = SULocalizedString(@"OK", nil);
        
        NSMutableDictionary *userInfo =
        [NSMutableDictionary dictionaryWithDictionary:@{
            NSLocalizedDescriptionKey: localizedDescription,
            NSLocalizedRecoverySuggestionErrorKey: recoverySuggestion,
            NSLocalizedRecoveryOptionsErrorKey: @[recoveryOption],
            SPUNoUpdateFoundReasonKey: @(reason),
            SPUNoUpdateFoundUserInitiatedKey: @(!background),
        }];
        
        if (latestAppcastItem != nil) {
            userInfo[SPULatestAppcastItemFoundKey] = latestAppcastItem;
        }
        
        NSError *notFoundError =
        [NSError
         errorWithDomain:SUSparkleErrorDomain
         code:SUNoUpdateError
         userInfo:[userInfo copy]];
        
        if ([self.updaterDelegate respondsToSelector:@selector((updaterDidNotFindUpdate:error:))]) {
            [self.updaterDelegate updaterDidNotFindUpdate:self.updater error:notFoundError];
        } else if ([self.updaterDelegate respondsToSelector:@selector((updaterDidNotFindUpdate:))]) {
            [self.updaterDelegate updaterDidNotFindUpdate:self.updater];
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidNotFindUpdateNotification object:self.updater userInfo:userInfo];
        
        [self.delegate basicDriverIsRequestingAbortUpdateWithError:notFoundError];
    }
}

- (void)abortUpdateAndShowNextUpdateImmediately:(BOOL)shouldShowUpdateImmediately resumableUpdate:(id<SPUResumableUpdate> _Nullable)resumableUpdate error:(nullable NSError *)error
{
    self.aborted = YES;
    
    [self.appcastDriver cleanup:^{
        if (self.completionBlock != nil) {
            self.completionBlock(shouldShowUpdateImmediately, resumableUpdate, error);
            self.completionBlock = nil;
        }
    }];
}

@end
