//
//  SPUUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUpdateDriver.h"
#import "SPUUserDriver.h"
#import "SUHost.h"
#import "SUConstants.h"
#import "SPUUpdaterDelegate.h"
#import "SUAppcastItem.h"
#import "SUErrors.h"
#import "SPUDownloadData.h"
#import "SPUReleaseNotesDriver.h"
#import "SPUSkippedUpdate.h"
#import "SPUUserUpdateState+Private.h"
#import "SUAppcastItem+Private.h"
#import "SPUUpdateCheck.h"
#import "SUAppcastDriver.h"
#import "SPUInstallerDriver.h"
#import "SPUDownloadDriver.h"
#import "SULog.h"
#import "SULog+NSError.h"
#import "SPUDownloadedUpdate.h"
#import "SPUInstallationType.h"
#import "SUPhasedUpdateGroupInfo.h"
#import "SPUProbeInstallStatus.h"
#import "SPUInstallationInfo.h"
#import "SUVersionDisplayProtocol.h"
#import "SPUStandardVersionDisplay.h"
#import "SPUNoUpdateFoundInfo.h"
#import "SUStandardVersionComparator.h"
#import "SULocalizations.h"


#include "AppKitPrevention.h"

// Note: critical updates can be downloaded automatically first before needing user attention
static BOOL SPUUpdateRequiresUserAttentionBeforeDownloading(SUAppcastItem *updateItem)
{
    return (updateItem.isInformationOnlyUpdate || updateItem.majorUpgrade || updateItem.signingValidationStatus == SPUAppcastSigningValidationStatusFailed);
}

@interface SPUUpdateDriver () <SUAppcastDriverDelegate, SPUDownloadDriverDelegate, SPUInstallerDriverDelegate>
@end

@implementation SPUUpdateDriver
{
    SUAppcastDriver *_appcastDriver;
    SPUDownloadDriver *_downloadDriver;
    SPUInstallerDriver *_installerDriver;

    SUHost *_host;
    id<SPUUserDriver> _userDriver;
    SPUReleaseNotesDriver *_releaseNotesDriver;
    NSDictionary *_httpHeaders;
    NSString *_userAgent;
    
    SUAppcastItem *_updateItem;
    SUAppcastItem * _Nullable _secondaryUpdateItem;
    
    SPUDownloadedUpdate *_resumableLocalUpdate;
    SPUDownloadedUpdate *_downloadedUpdateForRemoval;
    
    SPUInstallationInfo *_pendingResumeInstallationInfo;
    
    NSDate *_lastImpatientCheckedDate;
    
    SPUUpdateDriverCompletion _completionBlock;
    void (^_updateShownHandler)(void);
    
    SPUUpdateDriverInstallMode _installMode;
    SPUUserUpdateStage _currentStage;
    
    NSTimeInterval _impatientUpdateCheckInterval;
    
    __weak id _updater;
    __weak id<SPUUpdaterDelegate> _updaterDelegate;
    
    BOOL _userInitiated;
    BOOL _startedResumingInstallingUpdate;
    BOOL _startedResumingDownloadedUpdate;
    BOOL _installerDidFinishPreparation;
    BOOL _showingUpdate;
    BOOL _showingUserInitiatedProgress;
    BOOL _aborted;
    BOOL _impatientIntervalElapsedForResumingInstall;
    BOOL _shouldResetImpatientCheckDate;
}

@synthesize showingUpdate = _showingUpdate;
@synthesize lastImpatientCheckedDate = _lastImpatientCheckedDate;
@synthesize impatientUpdateCheckInterval = _impatientUpdateCheckInterval;

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate userInitiated:(BOOL)userInitiated installMode:(SPUUpdateDriverInstallMode)installMode
{
    self = [super init];
    if (self != nil) {
        _host = host;
        _userDriver = userDriver;
        _updater = updater;
        _updaterDelegate = updaterDelegate;
        _userInitiated = userInitiated;
        _installMode = installMode;
        _lastImpatientCheckedDate = [NSDate date];
        
        _appcastDriver = [[SUAppcastDriver alloc] initWithHost:host updater:updater updaterDelegate:updaterDelegate delegate:self];
        _installerDriver = [[SPUInstallerDriver alloc] initWithHost:host applicationBundle:applicationBundle updater:updater updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)setCompletionHandler:(SPUUpdateDriverCompletion)completionBlock
{
    _completionBlock = [completionBlock copy];
}

- (void)setUpdateShownHandler:(void (^)(void))updateShownHandler
{
    _updateShownHandler = [updateShownHandler copy];
}

- (void)setUpdateWillInstallHandler:(void (^)(void))updateWillInstallHandler
{
    [_installerDriver setUpdateWillInstallHandler:updateWillInstallHandler];
}

#pragma mark - Preparing to check for updates

- (void)fireUpdateShownHandlerIfNeeded SPU_OBJC_DIRECT
{
    if (_updateShownHandler != nil) {
        _updateShownHandler();
        _updateShownHandler = nil;
    }
}

#pragma mark - Checking for updates

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders resumingLocalUpdate:(SPUDownloadedUpdate * _Nullable)resumableLocalUpdate
{
    _httpHeaders = httpHeaders;
    _userAgent = [userAgent copy];

    if (_userInitiated) {
        [SPUSkippedUpdate clearSkippedUpdateForHost:_host];

        _showingUserInitiatedProgress = YES;

        [self fireUpdateShownHandlerIfNeeded];

        [_userDriver showUserInitiatedUpdateCheckWithCancellation:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self->_showingUserInitiatedProgress) {
                    [self abortUpdateWithError:nil];
                }
            });
        }];
    }

    __weak __typeof__(self) weakSelf = self;
    NSString *hostBundleIdentifier = _host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    [SPUProbeInstallStatus probeInstallerUpdateItemForHostBundleIdentifier:hostBundleIdentifier completion:^(SPUInstallationInfo * _Nullable installationInfo) {
        dispatch_async(dispatch_get_main_queue(), ^{
            __typeof__(self) strongSelf = weakSelf;
            if (strongSelf == nil) {
                return;
            }
            
            if (installationInfo != nil) {
                // An external installer job (eg: from another instance of the updater) is already
                // staging or installing an update - that takes priority over resumableLocalUpdate
                strongSelf->_startedResumingInstallingUpdate = YES;

                if (installationInfo.systemDomain || ![strongSelf->_host.bundle isEqual:NSBundle.mainBundle]) {
                    // When an update required auth or when updating another bundle that may
                    // have been started by another updater, don't risk canceling it
                    [strongSelf notifyFoundValidUpdateWithAppcastItem:installationInfo.appcastItem secondaryAppcastItem:nil systemDomain:@(installationInfo.systemDomain) resumingExistingUpdate:YES];
                    return;
                }

                strongSelf->_pendingResumeInstallationInfo = installationInfo;
            } else if (resumableLocalUpdate != nil) {
                strongSelf->_startedResumingDownloadedUpdate = YES;
                strongSelf->_resumableLocalUpdate = resumableLocalUpdate;
            }
            
            if ([strongSelf->_host isRunningOnReadOnlyVolume]) {
                NSString *hostName = strongSelf->_host.name;
#if SPARKLE_COPY_LOCALIZATIONS
                NSBundle *sparkleBundle = SUSparkleBundle();
#endif

                if ([strongSelf->_host isRunningTranslocated]) {
                    [strongSelf abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURunningTranslocated userInfo:@{ NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"Quit %1$@, move it into your Applications folder, relaunch it from there and try again.", SPARKLE_TABLE, sparkleBundle, nil), hostName], NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%1$@ can’t be updated if it’s running from the location it was downloaded to.", SPARKLE_TABLE, sparkleBundle, nil), hostName], }]];
                } else {
                    [strongSelf abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURunningFromDiskImageError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%1$@ can’t be updated because it was opened from a read-only or a temporary location.", SPARKLE_TABLE, sparkleBundle, nil), hostName], NSLocalizedRecoverySuggestionErrorKey: [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"Use Finder to copy %1$@ to the Applications folder, relaunch it from there, and try again.", SPARKLE_TABLE, sparkleBundle, nil), hostName] }]];
                }
            } else {
                BOOL resumingUpdate = (installationInfo != nil || resumableLocalUpdate != nil);
                [strongSelf->_appcastDriver loadAppcastFromURL:appcastURL userAgent:userAgent httpHeaders:httpHeaders inBackground:!strongSelf->_userInitiated resumingUpdate:resumingUpdate];
            }
        });
    }];
}

#pragma mark - SUAppcastDriverDelegate

- (void)didFailToFetchAppcastWithError:(NSError *)error
{
    if (!_aborted) {
        if (_pendingResumeInstallationInfo != nil) {
            SUAppcastItem *pendingItem = _pendingResumeInstallationInfo.appcastItem;
            BOOL pendingSystemDomain = _pendingResumeInstallationInfo.systemDomain;
            _pendingResumeInstallationInfo = nil;

            // The appcast check itself failed, so pretend it finished loading so drivers stop showing fetching progress
            [self notifyFoundValidUpdateWithAppcastItem:pendingItem secondaryAppcastItem:nil systemDomain:@(pendingSystemDomain) resumingExistingUpdate:YES];
            return;
        } else if (_resumableLocalUpdate != nil) {
            [self notifyFoundValidUpdateWithAppcastItem:_resumableLocalUpdate.updateItem secondaryAppcastItem:_resumableLocalUpdate.secondaryUpdateItem systemDomain:nil resumingExistingUpdate:YES];
            return;
        }

        [self abortUpdateWithError:error];
    }
}

- (void)didFinishLoadingAppcast:(SUAppcast *)appcast
{
    if (!_aborted) {
        id <SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
        if ([updaterDelegate respondsToSelector:@selector((updater:didFinishLoadingAppcast:))]) {
            [updaterDelegate updater:_updater didFinishLoadingAppcast:appcast];
        }
    }
}

- (void)notifyFoundValidUpdateWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryUpdateItem systemDomain:(NSNumber * _Nullable)systemDomain resumingExistingUpdate:(BOOL)resumingExistingUpdate SPU_OBJC_DIRECT
{
    if (!_aborted) {
        id <SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
        id updater = _updater;
        
        if (!resumingExistingUpdate) {
            // Give the delegate a chance to bail
            
            SPUUpdateCheck updateCheck;
            if (_userInitiated) {
                updateCheck = SPUUpdateCheckUpdates;
            } else if (_installMode == SPUUpdateDriverInstallModeShowingUI || _installMode == SPUUpdateDriverInstallModeAutomatic) {
                updateCheck = SPUUpdateCheckUpdatesInBackground;
            } else {
                updateCheck = SPUUpdateCheckUpdateInformation;
            }
            
            NSError *shouldNotProceedError = nil;
            if ([updaterDelegate respondsToSelector:@selector(updater:shouldProceedWithUpdate:updateCheck:error:)] && ![updaterDelegate updater:updater shouldProceedWithUpdate:updateItem updateCheck:updateCheck error:&shouldNotProceedError]) {
                [self abortUpdateWithError:(shouldNotProceedError != nil) ? shouldNotProceedError : [NSError errorWithDomain:SUSparkleErrorDomain code:SUUpdateCheckDeclinedError userInfo:nil]];
                return;
            }
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFindValidUpdateNotification
                                                            object:updater
                                                          userInfo:@{ SUUpdaterAppcastItemNotificationKey: updateItem }];
        
        if ([updaterDelegate respondsToSelector:@selector((updater:didFindValidUpdate:))]) {
            [updaterDelegate updater:updater didFindValidUpdate:updateItem];
        }

        _updateItem = updateItem;
        _secondaryUpdateItem = secondaryUpdateItem;

        if (resumingExistingUpdate && _startedResumingInstallingUpdate) {
            assert(systemDomain != nil);
            [_installerDriver resumeInstallingUpdateWithUpdateItem:updateItem systemDomain:systemDomain.boolValue];
        }

        if (_installMode == SPUUpdateDriverInstallModeNone) {
            // Probing: stop as soon as we have an answer
            [self abortUpdateWithError:nil];
            return;
        }
        
        if (resumingExistingUpdate) {
            if (_startedResumingInstallingUpdate) {
                _currentStage = SPUUserUpdateStageInstalling;
            } else if (_startedResumingDownloadedUpdate) {
                _currentStage = SPUUserUpdateStageDownloaded;
            } else {
                assert(false);
            }
        } else {
            _currentStage = SPUUserUpdateStageNotDownloaded;
        }

        if (_installMode == SPUUpdateDriverInstallModeShowingUI) {
            [self presentUpdateFoundWithAppcastItem:updateItem secondaryAppcastItem:secondaryUpdateItem];
            return;
        }

        // For automatic install mode, if we are resuming an installing update we will
        // check if impatient interval elapsed, otherwise the last impatient update check date
        // will be refreshed (when downloading a new fresh update or escalating to showing UI)
        if (resumingExistingUpdate) {
            if (_startedResumingInstallingUpdate) {
                // The update has already finished preparation from a previous cycle
                _installerDidFinishPreparation = YES;

                NSTimeInterval intervalSinceImpatientDate = [[NSDate date] timeIntervalSinceDate:_lastImpatientCheckedDate];
                _impatientIntervalElapsedForResumingInstall = (intervalSinceImpatientDate >= _impatientUpdateCheckInterval);
            }
            // This will escalate to showing UI if !_startedResumingInstallingUpdate
            // because _installerDidFinishPreparation is NO
            [self finishOrEscalateAutomaticCycleWithError:nil];
        } else {
            if (SPUUpdateRequiresUserAttentionBeforeDownloading(updateItem)) {
                // Escalate to showing UI right now for this item, rather than deferring to a later cycle
                [self escalateToShowingUI];
                [self presentUpdateFoundWithAppcastItem:updateItem secondaryAppcastItem:secondaryUpdateItem];
            } else {
                _shouldResetImpatientCheckDate = YES;
                [self downloadUpdateFromAppcastItem:updateItem secondaryAppcastItem:secondaryUpdateItem inBackground:YES];
            }
        }
    }
}

- (BOOL)pendingUpdateItem:(SUAppcastItem *)pendingUpdateItem isSupersededByUpdateItem:(SUAppcastItem *)newUpdateItem SPU_OBJC_DIRECT
{
    id<SUVersionComparison> versionComparator = nil;
    id<SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
    id updater = _updater;
    if (updater != nil && [updaterDelegate respondsToSelector:@selector(versionComparatorForUpdater:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        versionComparator = [updaterDelegate versionComparatorForUpdater:updater];
#pragma clang diagnostic pop
    }
    if (versionComparator == nil) {
        versionComparator = [SUStandardVersionComparator defaultComparator];
    }
    
    return ([versionComparator compareVersion:pendingUpdateItem.versionString toVersion:newUpdateItem.versionString] == NSOrderedAscending);
}

- (void)didFindValidUpdateWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryAppcastItem
{
    if (_pendingResumeInstallationInfo != nil) {
        SUAppcastItem *pendingItem = _pendingResumeInstallationInfo.appcastItem;
        BOOL pendingSystemDomain = _pendingResumeInstallationInfo.systemDomain;
        _pendingResumeInstallationInfo = nil;

        if (![self pendingUpdateItem:pendingItem isSupersededByUpdateItem:updateItem]) {
            [self notifyFoundValidUpdateWithAppcastItem:pendingItem secondaryAppcastItem:nil systemDomain:@(pendingSystemDomain) resumingExistingUpdate:YES];
            return;
        }
        
        // No need to discard the prior resumable installed update.
        // The update will be discarded when we submit new installer job
    } else if (_resumableLocalUpdate != nil) {
        if (![self pendingUpdateItem:_resumableLocalUpdate.updateItem isSupersededByUpdateItem:updateItem]) {
            [self notifyFoundValidUpdateWithAppcastItem:_resumableLocalUpdate.updateItem secondaryAppcastItem:_resumableLocalUpdate.secondaryUpdateItem systemDomain:nil resumingExistingUpdate:YES];
            return;
        } else {
            // Discard stale resumable update
            [self clearDownloadedUpdate];
        }
    }

    [self notifyFoundValidUpdateWithAppcastItem:updateItem secondaryAppcastItem:secondaryAppcastItem systemDomain:nil resumingExistingUpdate:NO];
}

- (void)didNotFindUpdateWithLatestAppcastItem:(nullable SUAppcastItem *)latestAppcastItem hostToLatestAppcastItemComparisonResult:(NSComparisonResult)hostToLatestAppcastItemComparisonResult background:(BOOL)background
{
    if (!_aborted) {
        if (_pendingResumeInstallationInfo != nil) {
            SUAppcastItem *pendingItem = _pendingResumeInstallationInfo.appcastItem;
            BOOL pendingSystemDomain = _pendingResumeInstallationInfo.systemDomain;
            _pendingResumeInstallationInfo = nil;

            [self notifyFoundValidUpdateWithAppcastItem:pendingItem secondaryAppcastItem:nil systemDomain:@(pendingSystemDomain) resumingExistingUpdate:YES];
            return;
        } else if (_resumableLocalUpdate != nil) {
            [self notifyFoundValidUpdateWithAppcastItem:_resumableLocalUpdate.updateItem secondaryAppcastItem:_resumableLocalUpdate.secondaryUpdateItem systemDomain:nil resumingExistingUpdate:YES];
            return;
        }

        NSString *localizedDescription;
        
#if SPARKLE_COPY_LOCALIZATIONS
        NSBundle *sparkleBundle = SUSparkleBundle();
#else
        NSBundle *sparkleBundle = nil;
#endif
        
        SPUNoUpdateFoundReason reason;
        if (latestAppcastItem != nil) {
            switch (hostToLatestAppcastItemComparisonResult) {
                case NSOrderedDescending:
                    // This means the user is a 'newer than latest' version. give a slight hint to the user instead of wrongly claiming this version is identical to the latest feed version.
                    localizedDescription = SULocalizedStringFromTableInBundle(@"You’re up to date!", SPARKLE_TABLE, sparkleBundle, "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
                    
                    reason = SPUNoUpdateFoundReasonOnNewerThanLatestVersion;
                    break;
                case NSOrderedSame:
                    // No new update is available and we're on the latest
                    localizedDescription = SULocalizedStringFromTableInBundle(@"You’re up to date!", SPARKLE_TABLE, sparkleBundle, "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
                    
                    reason = SPUNoUpdateFoundReasonOnLatestVersion;
                    break;
                case NSOrderedAscending:
                    // A new update is available but cannot be installed
                    // More detailed recovery suggestions are in SPUNoUpdateFoundRecoverySuggestion()
                    
                    if (!latestAppcastItem.arm64HardwareRequirementIsOK) {
                        localizedDescription = SULocalizedStringFromTableInBundle(@"Your Mac is too old", SPARKLE_TABLE, sparkleBundle, nil);
                        
                        reason = SPUNoUpdateFoundReasonHardwareDoesNotSupportARM64;
                    } else if (!latestAppcastItem.minimumOperatingSystemVersionIsOK) {
                        localizedDescription = SULocalizedStringFromTableInBundle(@"Your macOS version is too old", SPARKLE_TABLE, sparkleBundle, nil);
                        
                        reason = SPUNoUpdateFoundReasonSystemIsTooOld;
                    } else if (!latestAppcastItem.maximumOperatingSystemVersionIsOK) {
                        localizedDescription = SULocalizedStringFromTableInBundle(@"Your macOS version is too new", SPARKLE_TABLE, sparkleBundle, nil);
                        
                        reason = SPUNoUpdateFoundReasonSystemIsTooNew;
                    } else {
                        // We shouldn't realistically get here
                        localizedDescription = SULocalizedStringFromTableInBundle(@"You’re up to date!", SPARKLE_TABLE, sparkleBundle, "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
                        
                        reason = SPUNoUpdateFoundReasonUnknown;
                    }
                    break;
            }
        } else {
            // When no updates are found in the appcast
            // We will need to assume the user is up to date if the feed doesn't have any applicable update items
            // There could be update items on channels the updater is not subscribed to for example. But we can't tell the user about them.
            // There could also only be update items available for other platforms or none at all.
            localizedDescription = SULocalizedStringFromTableInBundle(@"You’re up to date!", SPARKLE_TABLE, sparkleBundle, "Status message shown when the user checks for updates but is already current or the feed doesn't contain any updates.");
            
            reason = SPUNoUpdateFoundReasonOnLatestVersion;
        }
        
        // We use the standard version displayer here to construct a reason string,
        // but it's possible for the user driver to override this before displaying if they wish
        id<SUVersionDisplay> versionDisplayer = [SPUStandardVersionDisplay standardVersionDisplay];
        NSString *recoverySuggestion = SPUNoUpdateFoundRecoverySuggestion(reason, latestAppcastItem, _host, versionDisplayer, sparkleBundle);
        
        NSString *recoveryOption = SULocalizedStringFromTableInBundle(@"OK", SPARKLE_TABLE, sparkleBundle, nil);
        
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
        
        [self abortUpdateWithError:notFoundError];
    }
}

#pragma mark - Finding an update

- (void)escalateToShowingUI SPU_OBJC_DIRECT
{
    _installMode = SPUUpdateDriverInstallModeShowingUI;
    _shouldResetImpatientCheckDate = YES;
}

- (void)presentUpdateFoundWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryUpdateItem SPU_OBJC_DIRECT
{
    id <SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
    SPUUserUpdateStage stage = _currentStage;
    
    SPUUserUpdateState *state = [[SPUUserUpdateState alloc] initWithStage:stage userInitiated:_userInitiated];
    
    [_userDriver showUpdateFoundWithAppcastItem:updateItem state:state reply:^(SPUUserUpdateChoice userChoice) {
        dispatch_async(dispatch_get_main_queue(), ^{
            
            // Rule out invalid choices
            SPUUserUpdateChoice validatedChoice;
            if (updateItem.isInformationOnlyUpdate && userChoice == SPUUserUpdateChoiceInstall) {
                validatedChoice = SPUUserUpdateChoiceDismiss;
            } else {
                validatedChoice = userChoice;
            }
            
            id updater = self->_updater;
            if (updater != nil) {
                if ([updaterDelegate respondsToSelector:@selector(updater:userDidMakeChoice:forUpdate:state:)]) {
                    [updaterDelegate updater:updater userDidMakeChoice:validatedChoice forUpdate:updateItem state:state];
                } else if (validatedChoice == SPUUserUpdateChoiceSkip && [updaterDelegate respondsToSelector:@selector(updater:userDidSkipThisVersion:)]) {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
                    [updaterDelegate updater:updater userDidSkipThisVersion:updateItem];
    #pragma clang diagnostic pop
                }
            }
            
            switch (validatedChoice) {
                case SPUUserUpdateChoiceInstall: {
                    switch (stage) {
                        case SPUUserUpdateStageDownloaded:
                            [self extractUpdate];
                            break;
                        case SPUUserUpdateStageInstalling:
                            [self finishInstallationWithResponse:validatedChoice displayingUserInterface:YES];
                            break;
                        case SPUUserUpdateStageNotDownloaded:
                            [self downloadUpdateFromAppcastItem:updateItem secondaryAppcastItem:secondaryUpdateItem inBackground:NO];
                            break;
                    }
                    break;
                }
                case SPUUserUpdateChoiceSkip: {
                    [SPUSkippedUpdate skipUpdate:updateItem host:self->_host];
                    
                    switch (stage) {
                        case SPUUserUpdateStageDownloaded:
                        case SPUUserUpdateStageNotDownloaded:
                            if (stage == SPUUserUpdateStageDownloaded) {
                                [self clearDownloadedUpdate];
                            }
                            
                            [self abortUpdateWithError:nil];
                            
                            break;
                        case SPUUserUpdateStageInstalling:
                            [self finishInstallationWithResponse:validatedChoice displayingUserInterface:YES];
                            break;
                    }
                    
                    break;
                }
                case SPUUserUpdateChoiceDismiss: {
                    switch (stage) {
                        case SPUUserUpdateStageDownloaded:
                        case SPUUserUpdateStageNotDownloaded: {
                            [self abortUpdateWithError:nil];
                            break;
                        }
                        case SPUUserUpdateStageInstalling: {
                            [self finishInstallationWithResponse:validatedChoice displayingUserInterface:YES];
                            break;
                        }
                    }
                    
                    break;
                }
            }
        });
    }];
    
    _showingUpdate = YES;
    [self fireUpdateShownHandlerIfNeeded];
    
    NSURL *releaseNotesURL = updateItem.releaseNotesURL;
    if (releaseNotesURL != nil && (![updaterDelegate respondsToSelector:@selector(updater:shouldDownloadReleaseNotesForUpdate:)] || [updaterDelegate updater:_updater shouldDownloadReleaseNotesForUpdate:updateItem])) {
        
        __weak __typeof__(self) weakSelf = self;
        _releaseNotesDriver = [[SPUReleaseNotesDriver alloc] initWithReleaseNotesURL:releaseNotesURL contentLength:updateItem.releaseNotesContentLength signatures:updateItem.releaseNotesSignatures httpHeaders:_httpHeaders userAgent:_userAgent host:_host completionHandler:^(SPUDownloadData * _Nullable downloadData, NSError * _Nullable error) {
            __typeof__(self) strongSelf = weakSelf;
            if (strongSelf != nil) {
                id <SPUUserDriver> userDriver = strongSelf->_userDriver;
                if (downloadData != nil) {
                    [userDriver showUpdateReleaseNotesWithDownloadData:(SPUDownloadData * _Nonnull)downloadData];
                } else {
                    [userDriver showUpdateReleaseNotesFailedToDownloadWithError:(NSError * _Nonnull)error];
                }
            }
        }];
        
        [_releaseNotesDriver startDownload];
    }
}

#pragma mark - Downloading (a no-op UI-wise while still silently downloading in automatic mode)

- (void)downloadUpdateFromAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryUpdateItem inBackground:(BOOL)background SPU_OBJC_DIRECT
{
    _downloadDriver = [[SPUDownloadDriver alloc] initWithUpdateItem:updateItem secondaryUpdateItem:secondaryUpdateItem host:_host userAgent:_userAgent httpHeaders:_httpHeaders inBackground:background delegate:self];
    
    id updater = _updater;
    id<SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
    
    if (updater != nil && [updaterDelegate respondsToSelector:@selector((updater:willDownloadUpdate:withRequest:))]) {
        [updaterDelegate updater:updater willDownloadUpdate:updateItem withRequest:_downloadDriver.request];
    }
    
    [_downloadDriver downloadFile];
}

- (void)downloadDriverWillBeginDownload
{
    if (_installMode != SPUUpdateDriverInstallModeShowingUI) {
        return;
    }
    
    void (^cancelDownload)(void) = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            id<SPUUpdaterDelegate> updaterDelegate = self->_updaterDelegate;
            if ([updaterDelegate respondsToSelector:@selector((userDidCancelDownload:))]) {
                [updaterDelegate userDidCancelDownload:self->_updater];
            }
            
            [self abortUpdateWithError:nil];
        });
    };
    
    [_userDriver showDownloadInitiatedWithCancellation:cancelDownload];
}

- (void)downloadDriverDidReceiveExpectedContentLength:(uint64_t)expectedContentLength
{
    if (_installMode != SPUUpdateDriverInstallModeShowingUI) {
        return;
    }
    [_userDriver showDownloadDidReceiveExpectedContentLength:expectedContentLength];
}

- (void)downloadDriverDidReceiveDataOfLength:(uint64_t)length
{
    if (_installMode != SPUUpdateDriverInstallModeShowingUI) {
        return;
    }
    [_userDriver showDownloadDidReceiveDataOfLength:length];
}

- (void)downloadDriverDidDownloadUpdate:(SPUDownloadedUpdate *)downloadedUpdate
{
    // Use a new update group for our next downloaded update
    // We could restrict this to when the appcast was downloaded in the background,
    // but it shouldn't matter.
    if (downloadedUpdate.updateItem.phasedRolloutInterval != nil) {
        [SUPhasedUpdateGroupInfo setNewUpdateGroupIdentifierForHost:_host];
    }
    
    id updater = _updater;
    id<SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
    
    if (updater != nil && [updaterDelegate respondsToSelector:@selector(updater:didDownloadUpdate:)]) {
        [updaterDelegate updater:updater didDownloadUpdate:_updateItem];
    }
    
    _resumableLocalUpdate = downloadedUpdate;
    [self extractUpdate];
}

- (void)downloadDriverDidFailToDownloadFileWithError:(NSError *)error
{
    if ([_updateItem isDeltaUpdate]) {
        SULog(SULogLevelError, @"Failed to download delta update. Falling back to regular update...");
        SULogError(error);

        [self fallBackAndDownloadRegularUpdate];
    } else {
        id updater = _updater;
        id<SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;

        if (updater != nil && [updaterDelegate respondsToSelector:@selector((updater:failedToDownloadUpdate:error:))]) {
            NSError *errorToReport = [error.userInfo objectForKey:NSUnderlyingErrorKey];
            if (errorToReport == nil) {
                errorToReport = error;
            }

            [updaterDelegate updater:updater failedToDownloadUpdate:_updateItem error:errorToReport];
        }

        [self abortUpdateWithError:error];
    }
}

- (void)fallBackAndDownloadRegularUpdate SPU_OBJC_DIRECT
{
    SUAppcastItem *secondaryUpdateItem = _secondaryUpdateItem;
    assert(secondaryUpdateItem != nil);

    BOOL backgroundDownload = _downloadDriver.inBackground;

    // Fall back to the non-delta update. Note that we don't want to trigger another update was found event.
    _updateItem = secondaryUpdateItem;
    _secondaryUpdateItem = nil;

    [self downloadUpdateFromAppcastItem:secondaryUpdateItem secondaryAppcastItem:nil inBackground:backgroundDownload];
}

#pragma mark - Extracting

- (void)extractUpdate SPU_OBJC_DIRECT
{
    SPUDownloadedUpdate *downloadedUpdate = _resumableLocalUpdate;
    assert(downloadedUpdate != nil);
    
    id updater = _updater;
    id<SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;

    if (updater != nil && [updaterDelegate respondsToSelector:@selector(updater:willExtractUpdate:)]) {
        [updaterDelegate updater:updater willExtractUpdate:_updateItem];
    }

    // Now we have to extract the downloaded archive.
    _currentStage = SPUUserUpdateStageDownloaded;
    if (_installMode == SPUUpdateDriverInstallModeShowingUI) {
        [_userDriver showDownloadDidStartExtractingUpdate];
    }
    
    [_installerDriver extractDownloadedUpdate:downloadedUpdate silently:(_installMode == SPUUpdateDriverInstallModeAutomatic) completion:^(NSError * _Nullable error) {
        if (error != nil) {
            if (error.code != SUInstallationAuthorizeLaterError) {
                [self clearDownloadedUpdate];
                [self abortUpdateWithError:error];
            } else {
                [self finishOrEscalateAutomaticCycleWithError:error];
            }
        } else {
            // If the installer started properly, we can't use the downloaded update archive anymore
            // Especially if the installer fails later and we try resuming the update with a missing archive file
            // We must clear the download after the installer begins using it however (in -installerDidStartInstalling)
            self->_downloadedUpdateForRemoval = downloadedUpdate;
            self->_resumableLocalUpdate = nil;

            if (updater != nil && [updaterDelegate respondsToSelector:@selector(updater:didExtractUpdate:)]) {
                [updaterDelegate updater:updater didExtractUpdate:self->_updateItem];
            }
        }
    }];
}

- (void)clearDownloadedUpdate SPU_OBJC_DIRECT
{
    SPUDownloadedUpdate *downloadedUpdate = (_resumableLocalUpdate != nil) ? _resumableLocalUpdate : _downloadedUpdateForRemoval;

    if (downloadedUpdate == nil) {
        SULog(SULogLevelError, @"Warning: clearDownloadedUpdate called but no downloaded update is tracked");
        return;
    }

    if (_downloadDriver == nil) {
        _downloadDriver = [[SPUDownloadDriver alloc] initWithHost:_host];
    }
    
    [_downloadDriver removeDownloadedUpdate:downloadedUpdate];
    
    // Clear any type of resumable update
    _resumableLocalUpdate = nil;
}

- (void)installerDidStartExtracting
{
    // The installer has moved the archive and no longer needs the download directory
    [self clearDownloadedUpdate];
}

- (void)installerDidExtractUpdateWithProgress:(double)progress
{
    if (_installMode != SPUUpdateDriverInstallModeShowingUI) {
        return;
    }
    [_userDriver showExtractionReceivedProgress:progress];
}

#pragma mark - Installing

- (void)installerDidStartInstallingWithApplicationTerminated:(BOOL)applicationTerminated
{
    if (_installMode != SPUUpdateDriverInstallModeShowingUI) {
        return;
    }
    
    if ([_userDriver respondsToSelector:@selector(showInstallingUpdateWithApplicationTerminated:retryTerminatingApplication:)]) {
        __weak __typeof__(self) weakSelf = self;
        [_userDriver showInstallingUpdateWithApplicationTerminated:applicationTerminated retryTerminatingApplication:^{
            if (!applicationTerminated) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    __typeof__(self) strongSelf = weakSelf;
                    if (strongSelf != nil) {
                        [strongSelf finishInstallationWithResponse:SPUUserUpdateChoiceInstall displayingUserInterface:YES];
                    }
                });
            }
        }];
    } else if ([_userDriver respondsToSelector:@selector(showInstallingUpdateWithApplicationTerminated:)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [_userDriver showInstallingUpdateWithApplicationTerminated:applicationTerminated];
#pragma clang diagnostic pop
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if ([_userDriver respondsToSelector:@selector(showInstallingUpdate)]) {
            [_userDriver showInstallingUpdate];
        }
        
        if (!applicationTerminated) {
            if ([_userDriver respondsToSelector:@selector(showSendingTerminationSignal)]) {
                [_userDriver showSendingTerminationSignal];
            }
        }
#pragma clang diagnostic pop
    }
}

#pragma mark - Ready to install

- (void)installerDidFinishPreparationAndWillInstallImmediately:(BOOL)willInstallImmediately
{
    _installerDidFinishPreparation = YES;
    _currentStage = SPUUserUpdateStageInstalling;
    
    if (willInstallImmediately) {
        return;
    }
    
    if (_installMode == SPUUpdateDriverInstallModeShowingUI) {
        [_userDriver showReadyToInstallAndRelaunch:^(SPUUserUpdateChoice choice) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self finishInstallationWithResponse:choice displayingUserInterface:YES];
            });
        }];
        
        _showingUpdate = YES;
        [self fireUpdateShownHandlerIfNeeded];
    } else {
        // Give the delegate a chance to handle installing on quit itself, bypassing Sparkle's own UI entirely -
        // this takes priority over escalating to show UI, even for a critical update
        id<SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
        BOOL installationHandledByDelegate;
        if ([updaterDelegate respondsToSelector:@selector(updater:willInstallUpdateOnQuit:immediateInstallationBlock:)]) {
            __weak __typeof__(self) weakSelf = self;
            installationHandledByDelegate = [updaterDelegate updater:_updater willInstallUpdateOnQuit:_updateItem immediateInstallationBlock:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    __typeof__(self) strongSelf = weakSelf;
                    if (strongSelf != nil) {
                        [strongSelf finishInstallationWithResponse:SPUUserUpdateChoiceInstall displayingUserInterface:NO];
                    }
                });
            }];
        } else {
            installationHandledByDelegate = NO;
        }
        
        if (!installationHandledByDelegate) {
            [self finishOrEscalateAutomaticCycleWithError:nil];
        }
    }
}

- (void)installerWillFinishInstallationAndRelaunch:(BOOL)relaunch
{
    id updater = _updater;
    id<SPUUpdaterDelegate> updaterDelegate = _updaterDelegate;
    
    if (updater != nil) {
        if ([updaterDelegate respondsToSelector:@selector((updater:willInstallUpdate:))]) {
            [updaterDelegate updater:updater willInstallUpdate:_updateItem];
        }
        
        if (relaunch) {
            [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterWillRestartNotification object:updater];
            if ([updaterDelegate respondsToSelector:@selector((updaterWillRelaunchApplication:))]) {
                [updaterDelegate updaterWillRelaunchApplication:updater];
            }
        }
    }
}

- (void)installerDidFinishInstallationAndRelaunched:(BOOL)relaunched acknowledgement:(void(^)(void))acknowledgement
{
    if (_installMode != SPUUpdateDriverInstallModeShowingUI) {
        acknowledgement();
        return;
    }
    
    if ([_userDriver respondsToSelector:@selector(showUpdateInstalledAndRelaunched:acknowledgement:)]) {
        [_userDriver showUpdateInstalledAndRelaunched:relaunched acknowledgement:acknowledgement];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [_userDriver showUpdateInstallationDidFinishWithAcknowledgement:acknowledgement];
#pragma clang diagnostic pop
    }
}

- (void)installerIsRequestingAbortInstallWithError:(nullable NSError *)error
{
    [self abortUpdateWithError:error];
}

- (void)installerDidFailToApplyDeltaUpdate
{
    [self clearDownloadedUpdate];
    
    [self fallBackAndDownloadRegularUpdate];
}

- (void)finishInstallationWithResponse:(SPUUserUpdateChoice)response displayingUserInterface:(BOOL)displayingUserInterface SPU_OBJC_DIRECT
{
    switch (response) {
        case SPUUserUpdateChoiceDismiss:
            [self abortUpdateWithError:nil];
            break;
        case SPUUserUpdateChoiceSkip:
            [_installerDriver cancelUpdate];
            break;
        case SPUUserUpdateChoiceInstall:
            [_installerDriver installWithToolAndRelaunch:YES displayingUserInterface:displayingUserInterface];
            break;
    }
}

#pragma mark - Ending a cycle

- (void)finishOrEscalateAutomaticCycleWithError:(nullable NSError *)error SPU_OBJC_DIRECT
{
    // Check if we need to escalate the automatic cycle into a UI one
    // If an error occurs it must be SUInstallationAuthorizeLaterError for escalation
    // if _updateItem == nil, we didn't get far enough in the driver to even find an update
    // If !_installerDidFinishPreparation, we didn't get far enough to prepare installing a new update
    // (e.g. it could be a local download resumable update).
    if ((error == nil || error.code == SUInstallationAuthorizeLaterError) &&
        (_updateItem != nil) &&
        (!_installerDidFinishPreparation || _updateItem.criticalUpdate || SPUUpdateRequiresUserAttentionBeforeDownloading(_updateItem) ||
         _impatientIntervalElapsedForResumingInstall)) {
        [self escalateToShowingUI];
        [self presentUpdateFoundWithAppcastItem:_updateItem secondaryAppcastItem:_secondaryUpdateItem];
    } else {
        [self finishWithError:error];
    }
}

- (void)abortUpdateWithError:(nullable NSError *)error
{
    if (_installMode == SPUUpdateDriverInstallModeShowingUI) {
        _showingUserInitiatedProgress = NO;
        _aborted = YES;
        
        BOOL showErrorToUser = _userInitiated || _showingUpdate;
        
        if (_releaseNotesDriver != nil) {
            [_releaseNotesDriver cleanup:^{
                [self abortShowingUIWithError:error showErrorToUser:showErrorToUser];
            }];
        } else {
            [self abortShowingUIWithError:error showErrorToUser:showErrorToUser];
        }
    } else {
        [self finishWithError:error];
    }
}

- (void)abortShowingUIWithError:(nullable NSError *)error showErrorToUser:(BOOL)showErrorToUser SPU_OBJC_DIRECT
{
    void (^finish)(void) = ^{
        if (showErrorToUser) {
            [self->_userDriver dismissUpdateInstallation];
        }
        [self finishWithError:error];
    };
    
    if (error != nil && showErrorToUser) {
        NSError *nonNullError = error;
        
        if (error.code == SUNoUpdateError) {
            if ([_userDriver respondsToSelector:@selector(showUpdateNotFoundWithError:acknowledgement:)]) {
                [_userDriver showUpdateNotFoundWithError:(NSError * _Nonnull)error acknowledgement:^{
                    dispatch_async(dispatch_get_main_queue(), ^{
                        finish();
                    });
                }];
            } else if ([_userDriver respondsToSelector:@selector(showUpdateNotFoundWithAcknowledgement:)]) {
                // Eventually we should remove this fallback once clients adopt -showUpdateNotFoundWithError:acknowledgement:
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                [_userDriver showUpdateNotFoundWithAcknowledgement:^{
#pragma clang diagnostic pop
                    dispatch_async(dispatch_get_main_queue(), ^{
                        finish();
                    });
                }];
            }
        } else if (error.code == SUInstallationCanceledError) {
            finish();
        } else {
            [_userDriver showUpdaterError:nonNullError acknowledgement:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    finish();
                });
            }];
        }
    } else {
        finish();
    }
}

- (void)finishWithError:(nullable NSError *)error SPU_OBJC_DIRECT
{
    [_installerDriver abortInstall];
    
    void (^finishAbort)(void) = ^{
        SPUDownloadedUpdate *resumableUpdate = (error == nil) ? self->_resumableLocalUpdate : nil;

        self->_aborted = YES;

        [self->_appcastDriver cleanup:^{
            if (self->_completionBlock != nil) {
                self->_completionBlock(self->_shouldResetImpatientCheckDate, resumableUpdate, error);
                self->_completionBlock = nil;
            }
        }];
    };
    
    if (_downloadDriver != nil) {
        [_downloadDriver cleanup:^{
            finishAbort();
        }];
    } else {
        finishAbort();
    }
}

@end
