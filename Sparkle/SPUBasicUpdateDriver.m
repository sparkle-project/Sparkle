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
#import "SPUInstallationType.h"


#include "AppKitPrevention.h"

@interface SPUBasicUpdateDriver () <SUAppcastDriverDelegate>

@end

@implementation SPUBasicUpdateDriver
{
    SUAppcastDriver *_appcastDriver;
    SUHost *_host;
    
    SPUUpdateDriverCompletion _completionBlock;
    
    SPUUpdateCheck _updateCheck;
    
    __weak id _updater;
    __weak id <SPUUpdaterDelegate> _updaterDelegate;
    __weak id<SPUBasicUpdateDriverDelegate> _delegate;
    
    BOOL _aborted;
}

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
    _completionBlock = [completionBlock copy];
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background
{
    if ([_host isRunningOnReadOnlyVolume]) {
        NSString *hostName = _host.name;
        id<SPUBasicUpdateDriverDelegate> delegate = _delegate;
        if ([_host isRunningTranslocated]) {
            [delegate basicDriverIsRequestingAbortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURunningTranslocated userInfo:@{ NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:SULocalizedString(@"Quit %1$@, move it into your Applications folder, relaunch it from there and try again.", nil), hostName], NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"%1$@ can’t be updated if it’s running from the location it was downloaded to.", nil), hostName], }]];
        } else {
            [delegate basicDriverIsRequestingAbortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURunningFromDiskImageError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"%1$@ can’t be updated, because it was opened from a read-only or a temporary location.", nil), hostName], NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:SULocalizedString(@"Use Finder to copy %1$@ to the Applications folder, relaunch it from there, and try again.", nil), hostName] }]];
        }
    } else {
        [_appcastDriver loadAppcastFromURL:appcastURL userAgent:userAgent httpHeaders:httpHeaders inBackground:background];
    }
}

- (void)notifyResumableUpdateItem:(SUAppcastItem *)updateItem secondaryUpdateItem:(SUAppcastItem * _Nullable)secondaryUpdateItem systemDomain:(NSNumber * _Nullable)systemDomain
{
    if (updateItem == nil) {
        [_delegate basicDriverIsRequestingAbortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUResumeAppcastError userInfo:@{ NSLocalizedDescriptionKey: SULocalizedString(@"Failed to resume installing update.", nil) }]];
    } else {
        // Kind of lying, but triggering the notification so drivers can know when to stop showing initial fetching progress
        [self notifyFinishLoadingAppcast];
        
        SUAppcastItem *nonNullUpdateItem = updateItem;
        [self notifyFoundValidUpdateWithAppcastItem:nonNullUpdateItem secondaryAppcastItem:secondaryUpdateItem systemDomain:systemDomain resuming:YES];
    }
}

- (void)resumeInstallingUpdate
{
    NSString *hostBundleIdentifier = _host.bundle.bundleIdentifier;
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
    if (!_aborted) {
        [_delegate basicDriverIsRequestingAbortUpdateWithError:error];
    }
}

- (void)notifyFinishLoadingAppcast
{
    id<SPUBasicUpdateDriverDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(basicDriverDidFinishLoadingAppcast)]) {
        [delegate basicDriverDidFinishLoadingAppcast];
    }
}

- (void)didFinishLoadingAppcast:(SUAppcast *)appcast
{
    if (!_aborted) {
        id <SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
        if ([updaterDelegate respondsToSelector:@selector((updater:didFinishLoadingAppcast:))]) {
            [updaterDelegate updater:_updater didFinishLoadingAppcast:appcast];
        }
        
        [self notifyFinishLoadingAppcast];
    }
}

- (void)notifyFoundValidUpdateWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryUpdateItem systemDomain:(NSNumber * _Nullable)systemDomain resuming:(BOOL)resuming
{
    if (!_aborted) {
        id<SPUBasicUpdateDriverDelegate> delegate = _delegate;
        id <SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
        id updater = _updater;
        
        if (!resuming) {
            // interactive pkg based updates are not supported under root user
            if ([updateItem.installationType isEqualToString:SPUInstallationTypeInteractivePackage] && geteuid() == 0) {
                [delegate basicDriverIsRequestingAbortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationRootInteractiveError userInfo:@{ NSLocalizedDescriptionKey: SULocalizedString(@"Interactive based packages cannot be installed as the root user.", nil) }]];
                return;
            } else {
                // Give the delegate a chance to bail
                
                NSError *shouldNotProceedError = nil;
                if ([updaterDelegate respondsToSelector:@selector(updater:shouldProceedWithUpdate:updateCheck:error:)] && ![updaterDelegate updater:updater shouldProceedWithUpdate:updateItem updateCheck:_updateCheck error:&shouldNotProceedError]) {
                    [delegate basicDriverIsRequestingAbortUpdateWithError:shouldNotProceedError];
                    return;
                }
            }
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFindValidUpdateNotification
                                                            object:updater
                                                          userInfo:@{ SUUpdaterAppcastItemNotificationKey: updateItem }];
        
        if ([updaterDelegate respondsToSelector:@selector((updater:didFindValidUpdate:))]) {
            [updaterDelegate updater:updater didFindValidUpdate:updateItem];
        }
        
        [delegate basicDriverDidFindUpdateWithAppcastItem:updateItem secondaryAppcastItem:secondaryUpdateItem systemDomain:systemDomain];
    }
}

- (void)didFindValidUpdateWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryAppcastItem
{
    [self notifyFoundValidUpdateWithAppcastItem:updateItem secondaryAppcastItem:secondaryAppcastItem systemDomain:nil resuming:NO];
}

- (void)didNotFindUpdateWithLatestAppcastItem:(nullable SUAppcastItem *)latestAppcastItem hostToLatestAppcastItemComparisonResult:(NSComparisonResult)hostToLatestAppcastItemComparisonResult background:(BOOL)background
{
    if (!_aborted) {
        NSString *localizedDescription;
        NSString *recoverySuggestion;
        
        SPUNoUpdateFoundReason reason;
        if (latestAppcastItem != nil) {
            switch (hostToLatestAppcastItemComparisonResult) {
                case NSOrderedDescending:
                    // This means the user is a 'newer than latest' version. give a slight hint to the user instead of wrongly claiming this version is identical to the latest feed version.
                    localizedDescription = SULocalizedString(@"You’re up-to-date!", "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
                    
                    recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.\n(You are currently running version %@.)", nil), [_host name], latestAppcastItem.displayVersionString, [_host displayVersion]];
                    
                    reason = SPUNoUpdateFoundReasonOnNewerThanLatestVersion;
                    break;
                case NSOrderedSame:
                    // No new update is available and we're on the latest
                    localizedDescription = SULocalizedString(@"You’re up-to-date!", "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
                    
                    recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.", nil), [_host name], [_host displayVersion]];
                    
                    reason = SPUNoUpdateFoundReasonOnLatestVersion;
                    break;
                case NSOrderedAscending:
                    // A new update is available but cannot be installed
                    
                    if (!latestAppcastItem.minimumOperatingSystemVersionIsOK) {
                        localizedDescription = SULocalizedString(@"Your macOS version is too old", nil);
                        
                        recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%1$@ %2$@ is available but your macOS version is too old to install it. At least macOS %3$@ is required.", nil), [_host name], latestAppcastItem.displayVersionString, latestAppcastItem.minimumSystemVersion];
                        
                        reason = SPUNoUpdateFoundReasonSystemIsTooOld;
                    } else if (!latestAppcastItem.maximumOperatingSystemVersionIsOK) {
                        localizedDescription = SULocalizedString(@"Your macOS version is too new", nil);
                        
                        recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%1$@ %2$@ is available but your macOS version is too new for this update. This update only supports up to macOS %3$@.", nil), [_host name], latestAppcastItem.displayVersionString, latestAppcastItem.maximumSystemVersion];
                        
                        reason = SPUNoUpdateFoundReasonSystemIsTooNew;
                    } else {
                        // We shouldn't realistically get here
                        localizedDescription = SULocalizedString(@"You’re up-to-date!", "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
                        
                        recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.", nil), [_host name], [_host displayVersion]];
                        
                        reason = SPUNoUpdateFoundReasonUnknown;
                    }
                    break;
            }
        } else {
            // When no updates are found in the appcast
            // We will need to assume the user is up to date if the feed doen't have any applicable update items
            // There could be update items on channels the updater is not subscribed to for example. But we can't tell the user about them.
            // There could also only be update items available for other platforms or none at all.
            localizedDescription = SULocalizedString(@"You’re up-to-date!", "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
            recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.", nil), [_host name], [_host displayVersion]];
            
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
        
        id <SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
        id updater = _updater;
        
        if (updater != nil) {
            if ([updaterDelegate respondsToSelector:@selector((updaterDidNotFindUpdate:error:))]) {
                [updaterDelegate updaterDidNotFindUpdate:updater error:notFoundError];
            } else if ([updaterDelegate respondsToSelector:@selector((updaterDidNotFindUpdate:))]) {
                [updaterDelegate updaterDidNotFindUpdate:updater];
            }
            
            [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidNotFindUpdateNotification object:updater userInfo:userInfo];
        }
        
        [_delegate basicDriverIsRequestingAbortUpdateWithError:notFoundError];
    }
}

- (void)abortUpdateAndShowNextUpdateImmediately:(BOOL)shouldShowUpdateImmediately resumableUpdate:(id<SPUResumableUpdate> _Nullable)resumableUpdate error:(nullable NSError *)error
{
    _aborted = YES;
    
    [_appcastDriver cleanup:^{
        if (self->_completionBlock != nil) {
            self->_completionBlock(shouldShowUpdateImmediately, resumableUpdate, error);
            self->_completionBlock = nil;
        }
    }];
}

@end
