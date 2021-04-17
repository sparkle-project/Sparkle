//
//  SPUUIBasedUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUIBasedUpdateDriver.h"
#import "SPUCoreBasedUpdateDriver.h"
#import "SPUUserDriver.h"
#import "SUHost.h"
#import "SUConstants.h"
#import "SPUUpdaterDelegate.h"
#import "SUAppcastItem.h"
#import "SUErrors.h"
#import "SPUURLDownload.h"
#import "SPUDownloadData.h"
#import "SPUResumableUpdate.h"


#include "AppKitPrevention.h"

@interface SPUUIBasedUpdateDriver() <SPUCoreBasedUpdateDriverDelegate>

@property (nonatomic, readonly) SPUCoreBasedUpdateDriver *coreDriver;
@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, weak, readonly) id updater;
@property (nonatomic, readonly) BOOL userInitiated;
@property (weak, nonatomic, readonly) id<SPUUpdaterDelegate> updaterDelegate;
@property (nonatomic, weak, readonly) id<SPUUIBasedUpdateDriverDelegate> delegate;
@property (nonatomic, readonly) id<SPUUserDriver> userDriver;
@property (nonatomic) BOOL resumingInstallingUpdate;
@property (nonatomic) BOOL resumingDownloadedUpdate;
@property (nonatomic) BOOL preventsInstallerInteraction;

@end

@implementation SPUUIBasedUpdateDriver

@synthesize coreDriver = _coreDriver;
@synthesize host = _host;
@synthesize updater = _updater;
@synthesize userInitiated = _userInitiated;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize userDriver = _userDriver;
@synthesize delegate = _delegate;
@synthesize resumingInstallingUpdate = _resumingInstallingUpdate;
@synthesize resumingDownloadedUpdate = _resumingDownloadedUpdate;
@synthesize preventsInstallerInteraction = _preventsInstallerInteraction;

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver userInitiated:(BOOL)userInitiated updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate delegate:(id<SPUUIBasedUpdateDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _userDriver = userDriver;
        _delegate = delegate;
        _updater = updater;
        _userInitiated = userInitiated;
        _updaterDelegate = updaterDelegate;
        _host = host;
        
        _coreDriver = [[SPUCoreBasedUpdateDriver alloc] initWithHost:host applicationBundle:applicationBundle sparkleBundle:sparkleBundle updater:updater updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)prepareCheckForUpdatesWithCompletion:(SPUUpdateDriverCompletion)completionBlock
{
    [self.coreDriver prepareCheckForUpdatesWithCompletion:completionBlock];
}

- (void)preflightForUpdatePermissionPreventingInstallerInteraction:(BOOL)preventsInstallerInteraction reply:(void (^)(NSError * _Nullable))reply
{
    self.preventsInstallerInteraction = preventsInstallerInteraction;
    
    [self.coreDriver preflightForUpdatePermissionPreventingInstallerInteraction:preventsInstallerInteraction reply:reply];
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background includesSkippedUpdates:(BOOL)includesSkippedUpdates
{
    [self.coreDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders inBackground:background includesSkippedUpdates:includesSkippedUpdates requiresSilentInstall:NO];
}

- (void)resumeInstallingUpdateWithCompletion:(SPUUpdateDriverCompletion)completionBlock
{
    self.resumingInstallingUpdate = YES;
    [self.coreDriver resumeInstallingUpdateWithCompletion:completionBlock];
}

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate completion:(SPUUpdateDriverCompletion)completionBlock
{
    // Informational downloads shouldn't be presented as updates to be downloaded
    // Neither should items that prevent auto updating
    if (!resumableUpdate.updateItem.isInformationOnlyUpdate && !resumableUpdate.preventsAutoupdate) {
        self.resumingDownloadedUpdate = YES;
    }
    [self.coreDriver resumeUpdate:resumableUpdate completion:completionBlock];
}

- (void)basicDriverDidFinishLoadingAppcast
{
    if ([self.delegate respondsToSelector:@selector(basicDriverDidFinishLoadingAppcast)]) {
        [self.delegate basicDriverDidFinishLoadingAppcast];
    }
}

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)updateItem preventsAutoupdate:(BOOL)preventsAutoupdate
{
    id <SPUUpdaterDelegate> updaterDelegate = self.updaterDelegate;
    if ([self.userDriver respondsToSelector:@selector(showUpdateFoundWithAppcastItem:userInitiated:state:reply:)]) {
        SPUUserUpdateState state;
        if (updateItem.isInformationOnlyUpdate) {
            state = SPUUserUpdateStateInformational;
        } else if (self.resumingDownloadedUpdate) {
            state = SPUUserUpdateStateDownloaded;
        } else if (self.resumingInstallingUpdate) {
            state = SPUUserUpdateStateInstalling;
        } else {
            state = SPUUserUpdateStateNotDownloaded;
        }
        
        [self.userDriver showUpdateFoundWithAppcastItem:updateItem userInitiated:self.userInitiated state:state reply:^(SPUUserUpdateChoice userChoice) {
            dispatch_async(dispatch_get_main_queue(), ^{
                
                // Rule out invalid choices
                SPUUserUpdateChoice validatedChoice;
                if ((state == SPUUserUpdateStateInstalling && userChoice == SPUUserUpdateChoiceSkip) || (state == SPUUserUpdateStateInformational && userChoice == SPUUserUpdateChoiceInstall)) {
                    validatedChoice = SPUUserUpdateChoiceDismiss;
                } else {
                    validatedChoice = userChoice;
                }
                
                switch (validatedChoice) {
                    case SPUUserUpdateChoiceInstall:
                        [self.host setObject:nil forUserDefaultsKey:SUSkippedVersionKey];
                        
                        switch (state) {
                            case SPUUserUpdateStateDownloaded:
                                [self.coreDriver extractDownloadedUpdate];
                                break;
                            case SPUUserUpdateStateInstalling:
                                [self.coreDriver finishInstallationWithResponse:validatedChoice displayingUserInterface:!self.preventsInstallerInteraction];
                                break;
                            case SPUUserUpdateStateNotDownloaded:
                                [self.coreDriver downloadUpdateFromAppcastItem:updateItem inBackground:NO];
                                break;
                            case SPUUserUpdateStateInformational:
                                assert(false);
                                break;
                        }
                        break;
                    case SPUUserUpdateChoiceSkip:
                        [self.host setObject:[updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
                        
                        if ([self.updaterDelegate respondsToSelector:@selector(updater:userDidSkipThisVersion:)]) {
                            [self.updaterDelegate updater:self.updater userDidSkipThisVersion:updateItem];
                        }
                        
                        [self.coreDriver clearDownloadedUpdate];
                        
                        [self.delegate uiDriverIsRequestingAbortUpdateWithError:nil];
                        
                        break;
                    case SPUUserUpdateChoiceDismiss:
                        switch (state) {
                            case SPUUserUpdateStateDownloaded:
                            case SPUUserUpdateStateNotDownloaded:
                            case SPUUserUpdateStateInformational:
                                [self.host setObject:nil forUserDefaultsKey:SUSkippedVersionKey];
                                [self.delegate uiDriverIsRequestingAbortUpdateWithError:nil];
                                break;
                            case SPUUserUpdateStateInstalling:
                                [self.coreDriver finishInstallationWithResponse:validatedChoice displayingUserInterface:!self.preventsInstallerInteraction];
                                break;
                        }
                        
                        break;
                }
            });
        }];
    } else {
        // Legacy path that will be removed eventually
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        if (updateItem.isInformationOnlyUpdate) {
            assert(!self.resumingDownloadedUpdate);
            assert(!self.resumingInstallingUpdate);
            
            [self.userDriver showInformationalUpdateFoundWithAppcastItem:updateItem userInitiated:self.userInitiated reply:^(SPUInformationalUpdateAlertChoice choice) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    switch (choice) {
                        case SPUSkipThisInformationalVersionChoice:
                            [self.host setObject:[updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
                            
                            if ([self.updaterDelegate respondsToSelector:@selector(updater:userDidSkipThisVersion:)]) {
                                [self.updaterDelegate updater:self.updater userDidSkipThisVersion:updateItem];
                            }
                            // Fall through
                        case SPUDismissInformationalNoticeChoice:
                            [self.delegate uiDriverIsRequestingAbortUpdateWithError:nil];
                            break;
                    }
                });
            }];
        } else if (self.resumingDownloadedUpdate) {
            [self.userDriver showDownloadedUpdateFoundWithAppcastItem:updateItem userInitiated:self.userInitiated reply:^(SPUUpdateAlertChoice choice) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.host setObject:nil forUserDefaultsKey:SUSkippedVersionKey];
                    switch (choice) {
                        case SPUInstallUpdateChoice:
                            [self.coreDriver extractDownloadedUpdate];
                            break;
                        case SPUSkipThisVersionChoice:
                            [self.coreDriver clearDownloadedUpdate];
                            [self.host setObject:[updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
                            
                            if ([self.updaterDelegate respondsToSelector:@selector(updater:userDidSkipThisVersion:)]) {
                                [self.updaterDelegate updater:self.updater userDidSkipThisVersion:updateItem];
                            }
                            // Fall through
                        case SPUInstallLaterChoice:
                            [self.delegate uiDriverIsRequestingAbortUpdateWithError:nil];
                            break;
                    }
                });
            }];
        } else if (!self.resumingInstallingUpdate) {
            [self.userDriver showUpdateFoundWithAppcastItem:updateItem userInitiated:self.userInitiated reply:^(SPUUpdateAlertChoice choice) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.host setObject:nil forUserDefaultsKey:SUSkippedVersionKey];
                    switch (choice) {
                        case SPUInstallUpdateChoice:
                            [self.coreDriver downloadUpdateFromAppcastItem:updateItem inBackground:NO];
                            break;
                        case SPUSkipThisVersionChoice:
                            [self.host setObject:[updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
                            
                            if ([self.updaterDelegate respondsToSelector:@selector(updater:userDidSkipThisVersion:)]) {
                                [self.updaterDelegate updater:self.updater userDidSkipThisVersion:updateItem];
                            }
                            // Fall through
                        case SPUInstallLaterChoice:
                            [self.delegate uiDriverIsRequestingAbortUpdateWithError:nil];
                            break;
                    }
                });
            }];
        } else {
            [self.userDriver showResumableUpdateFoundWithAppcastItem:updateItem userInitiated:self.userInitiated reply:^(SPUUserUpdateChoice choice) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.host setObject:nil forUserDefaultsKey:SUSkippedVersionKey];
                    [self.coreDriver finishInstallationWithResponse:choice displayingUserInterface:!self.preventsInstallerInteraction];
                });
            }];
        }
#pragma clang diagnostic pop
    }
    
    if ([self.delegate respondsToSelector:@selector(uiDriverDidShowUpdate)]) {
        [self.delegate uiDriverDidShowUpdate];
    }
    
    if (updateItem.releaseNotesURL != nil && (![updaterDelegate respondsToSelector:@selector(updaterShouldDownloadReleaseNotes:)] || [updaterDelegate updaterShouldDownloadReleaseNotes:self.updater])) {
        NSURLRequest *request = [NSURLRequest requestWithURL:updateItem.releaseNotesURL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30];
        
        id <SPUUserDriver> userDriver = self.userDriver;
        SPUDownloadURLWithRequest(request, ^(SPUDownloadData * _Nullable downloadData, NSError * _Nullable error) {
            if (downloadData != nil) {
                [userDriver showUpdateReleaseNotesWithDownloadData:(SPUDownloadData * _Nonnull)downloadData];
            } else {
                [userDriver showUpdateReleaseNotesFailedToDownloadWithError:(NSError * _Nonnull)error];
            }
        });
    }
}

- (void)downloadDriverWillBeginDownload
{
    void (^cancelDownload)(void) = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.updaterDelegate respondsToSelector:@selector((userDidCancelDownload:))]) {
                [self.updaterDelegate userDidCancelDownload:self.updater];
            }
            
            [self.delegate uiDriverIsRequestingAbortUpdateWithError:nil];
        });
    };
    
    if ([self.userDriver respondsToSelector:@selector(showDownloadInitiatedWithCancellation:)]) {
        [self.userDriver showDownloadInitiatedWithCancellation:cancelDownload];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [self.userDriver showDownloadInitiatedWithCompletion:^(SPUDownloadUpdateStatus downloadCompletionStatus) {
            switch (downloadCompletionStatus) {
#pragma clang diagnostic pop
                case SPUDownloadUpdateDone:
                    break;
                case SPUDownloadUpdateCanceled:
                    cancelDownload();
                    break;
            }
        }];
    }
}

- (void)downloadDriverDidReceiveExpectedContentLength:(uint64_t)expectedContentLength
{
    [self.userDriver showDownloadDidReceiveExpectedContentLength:expectedContentLength];
}

- (void)downloadDriverDidReceiveDataOfLength:(uint64_t)length
{
    [self.userDriver showDownloadDidReceiveDataOfLength:length];
}

- (void)coreDriverDidStartExtractingUpdate
{
    [self.userDriver showDownloadDidStartExtractingUpdate];
}

- (void)installerDidStartInstalling
{
    [self.userDriver showInstallingUpdate];
}

- (void)installerDidExtractUpdateWithProgress:(double)progress
{
    [self.userDriver showExtractionReceivedProgress:progress];
}

- (void)installerDidFinishPreparationAndWillInstallImmediately:(BOOL)willInstallImmediately silently:(BOOL)__unused willInstallSilently
{
    if (!willInstallImmediately) {
        [self.userDriver showReadyToInstallAndRelaunch:^(SPUUserUpdateChoice choice) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.coreDriver finishInstallationWithResponse:choice displayingUserInterface:!self.preventsInstallerInteraction];
            });
        }];
    }
}

- (void)installerIsSendingAppTerminationSignal
{
    [self.userDriver showSendingTerminationSignal];
}

- (void)installerDidFinishInstallationAndRelaunched:(BOOL)relaunched acknowledgement:(void(^)(void))acknowledgement
{
    if ([self.userDriver respondsToSelector:@selector(showUpdateInstalledAndRelaunched:acknowledgement:)]) {
        [self.userDriver showUpdateInstalledAndRelaunched:relaunched acknowledgement:acknowledgement];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [self.userDriver showUpdateInstallationDidFinishWithAcknowledgement:acknowledgement];
#pragma clang diagnostic pop
    }
}

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    // A delegate may want to handle this type of error specially
    [self.delegate basicDriverIsRequestingAbortUpdateWithError:error];
}

- (void)coreDriverIsRequestingAbortUpdateWithError:(NSError *)error
{
    // A delegate may want to handle this type of error specially
    [self.delegate coreDriverIsRequestingAbortUpdateWithError:error];
}

- (void)abortUpdateWithError:(nullable NSError *)error
{
    void (^abortUpdate)(void) = ^{
        [self.userDriver dismissUpdateInstallation];
        [self.coreDriver abortUpdateAndShowNextUpdateImmediately:NO error:error];
    };
    
    if (error != nil) {
        NSError *nonNullError = error;
        
        if (error.code == SUNoUpdateError) {
            if ([self.userDriver respondsToSelector:@selector(showUpdateNotFoundWithError:acknowledgement:)]) {
                [self.userDriver showUpdateNotFoundWithError:(NSError * _Nonnull)error acknowledgement:^{
                    dispatch_async(dispatch_get_main_queue(), ^{
                        abortUpdate();
                    });
                }];
            } else if ([self.userDriver respondsToSelector:@selector(showUpdateNotFoundWithAcknowledgement:)]) {
                // Eventually we should remove this fallback once clients adopt -showUpdateNotFoundWithError:acknowledgement:
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
                [self.userDriver showUpdateNotFoundWithAcknowledgement:^{
#pragma clang diagnostic pop
                    dispatch_async(dispatch_get_main_queue(), ^{
                        abortUpdate();
                    });
                }];
            }
        } else if (error.code == SUInstallationCanceledError || error.code == SUInstallationAuthorizeLaterError) {
            abortUpdate();
        } else {
            [self.userDriver showUpdaterError:nonNullError acknowledgement:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    abortUpdate();
                });
            }];
        }
    } else {
        abortUpdate();
    }
}

@end
