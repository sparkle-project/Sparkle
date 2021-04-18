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

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background includesSkippedUpdates:(BOOL)includesSkippedUpdates
{
    if ([self.host isRunningOnReadOnlyVolume]) {
        NSString *hostName = self.host.name;
        if ([self.host isRunningTranslocated]) {
            [self.delegate basicDriverIsRequestingAbortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURunningTranslocated userInfo:@{ NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:SULocalizedString(@"Quit %1$@, move it into your Applications folder, relaunch it from there and try again.", nil), hostName], NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"%1$@ can’t be updated if it’s running from the location it was downloaded to.", nil), hostName], }]];
        } else {
            [self.delegate basicDriverIsRequestingAbortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURunningFromDiskImageError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"%1$@ can't be updated, because it was opened from a read-only or a temporary location.", nil), hostName], NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:SULocalizedString(@"Use Finder to copy %1$@ to the Applications folder, relaunch it from there, and try again.", nil), hostName] }]];
        }
    } else {
        [self.appcastDriver loadAppcastFromURL:appcastURL userAgent:userAgent httpHeaders:httpHeaders inBackground:background includesSkippedUpdates:includesSkippedUpdates];
    }
}

- (void)notifyResumableUpdateItem:(SUAppcastItem *)updateItem systemDomain:(NSNumber * _Nullable)systemDomain
{
    if (updateItem == nil) {
        [self.delegate basicDriverIsRequestingAbortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUResumeAppcastError userInfo:@{ NSLocalizedDescriptionKey: SULocalizedString(@"Failed to resume installing update.", nil) }]];
    } else {
        // Kind of lying, but triggering the notification so drivers can know when to stop showing initial fetching progress
        [self notifyFinishLoadingAppcast];
        
        SUAppcastItem *nonNullUpdateItem = updateItem;
        [self notifyFoundValidUpdateWithAppcastItem:nonNullUpdateItem preventsAutoupdate:NO systemDomain:systemDomain];
    }
}

- (void)resumeInstallingUpdateWithCompletion:(SPUUpdateDriverCompletion)completionBlock
{
    self.completionBlock = completionBlock;
    
    NSString *hostBundleIdentifier = self.host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    [SPUProbeInstallStatus probeInstallerUpdateItemForHostBundleIdentifier:hostBundleIdentifier completion:^(SPUInstallationInfo * _Nullable installationInfo) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self notifyResumableUpdateItem:installationInfo.appcastItem systemDomain:@(installationInfo.systemDomain)];
        });
    }];
}

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate completion:(SPUUpdateDriverCompletion)completionBlock
{
    self.completionBlock = completionBlock;
    
    [self notifyResumableUpdateItem:resumableUpdate.updateItem systemDomain:nil];
}

- (SUAppcastItem *)nonDeltaUpdateItem
{
    return self.appcastDriver.nonDeltaUpdateItem;
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

- (void)notifyFoundValidUpdateWithAppcastItem:(SUAppcastItem *)updateItem preventsAutoupdate:(BOOL)preventsAutoupdate systemDomain:(NSNumber * _Nullable)systemDomain
{
    if (!self.aborted) {
        [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFindValidUpdateNotification
                                                            object:self.updater
                                                          userInfo:@{ SUUpdaterAppcastItemNotificationKey: updateItem }];
        
        if ([self.updaterDelegate respondsToSelector:@selector((updater:didFindValidUpdate:))]) {
            [self.updaterDelegate updater:self.updater didFindValidUpdate:updateItem];
        }
        
        [self.delegate basicDriverDidFindUpdateWithAppcastItem:updateItem preventsAutoupdate:preventsAutoupdate systemDomain:systemDomain];
    }
}

- (void)didFindValidUpdateWithAppcastItem:(SUAppcastItem *)updateItem preventsAutoupdate:(BOOL)preventsAutoupdate
{
    [self notifyFoundValidUpdateWithAppcastItem:updateItem preventsAutoupdate:preventsAutoupdate systemDomain:nil];
}

- (void)didNotFindUpdateWithLatestAppcastItem:(nullable SUAppcastItem *)latestAppcastItem hostToLatestAppcastItemComparisonResult:(NSComparisonResult)hostToLatestAppcastItemComparisonResult
{
    if (!self.aborted) {
        if ([self.updaterDelegate respondsToSelector:@selector((updaterDidNotFindUpdate:))]) {
            [self.updaterDelegate updaterDidNotFindUpdate:self.updater];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidNotFindUpdateNotification object:self.updater];
        
        NSString *localizedDescription;
        NSString *recoverySuggestion;
        NSString *recoveryOption;
        
        if (latestAppcastItem != nil) { // if the appcast was successfully loaded
            localizedDescription = SULocalizedString(@"You're up-to-date!", "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
            
            if (hostToLatestAppcastItemComparisonResult == NSOrderedDescending) { // this means the user is a 'newer than latest' version. give a slight hint to the user instead of wrongly claiming this version is identical to the latest feed version.
                recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.\n(You are currently running version %@.)", nil), [self.host name], latestAppcastItem.displayVersionString, [self.host displayVersion]];
            } else {
                recoverySuggestion = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.", nil), [self.host name], [self.host displayVersion]];
            }
            
            recoveryOption = @"OK";
        } else {
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
}

@end
