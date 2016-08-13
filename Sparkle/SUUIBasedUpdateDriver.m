//
//  SUUIBasedUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUIBasedUpdateDriver.h"
#import "SUCoreBasedUpdateDriver.h"
#import "SPUUserDriver.h"
#import "SUHost.h"
#import "SUConstants.h"
#import "SPUUpdaterDelegate.h"
#import "SUAppcastItem.h"
#import "SUErrors.h"
#import "SPUURLDownload.h"
#import "SPUDownloadData.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUUIBasedUpdateDriver() <SUCoreBasedUpdateDriverDelegate>

@property (nonatomic, readonly) SUCoreBasedUpdateDriver *coreDriver;
@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, weak, readonly) id updater;
@property (weak, nonatomic, readonly) id<SPUUpdaterDelegate> updaterDelegate;
@property (nonatomic, weak, readonly) id<SUUIBasedUpdateDriverDelegate> delegate;
@property (nonatomic, readonly) id<SPUUserDriver> userDriver;
@property (nonatomic) BOOL resumingInstallingUpdate;
@property (nonatomic) BOOL resumingDownloadedUpdate;

@end

@implementation SUUIBasedUpdateDriver

@synthesize coreDriver = _coreDriver;
@synthesize host = _host;
@synthesize updater = _updater;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize userDriver = _userDriver;
@synthesize delegate = _delegate;
@synthesize resumingInstallingUpdate = _resumingInstallingUpdate;
@synthesize resumingDownloadedUpdate = _resumingDownloadedUpdate;

- (instancetype)initWithHost:(SUHost *)host sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater userDriver:(id <SPUUserDriver>)userDriver updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate delegate:(id<SUUIBasedUpdateDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _userDriver = userDriver;
        _delegate = delegate;
        _updater = updater;
        _updaterDelegate = updaterDelegate;
        _host = host;
        
        _coreDriver = [[SUCoreBasedUpdateDriver alloc] initWithHost:host sparkleBundle:sparkleBundle updater:updater updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders includesSkippedUpdates:(BOOL)includesSkippedUpdates completion:(SUUpdateDriverCompletion)completionBlock
{
    [self.coreDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders includesSkippedUpdates:includesSkippedUpdates requiresSilentInstall:NO completion:completionBlock];
}

- (void)resumeInstallingUpdateWithCompletion:(SUUpdateDriverCompletion)completionBlock
{
    self.resumingInstallingUpdate = YES;
    [self.coreDriver resumeInstallingUpdateWithCompletion:completionBlock];
}

- (void)resumeDownloadedUpdate:(SUDownloadedUpdate *)downloadedUpdate completion:(SUUpdateDriverCompletion)completionBlock
{
    self.resumingDownloadedUpdate = YES;
    [self.coreDriver resumeDownloadedUpdate:downloadedUpdate completion:completionBlock];
}

- (void)basicDriverDidFinishLoadingAppcast
{
    if ([self.delegate respondsToSelector:@selector(basicDriverDidFinishLoadingAppcast)]) {
        [self.delegate basicDriverDidFinishLoadingAppcast];
    }
}

- (BOOL)canDisplayInstallerUserInterface
{
    // Are we allowed to perform updates that may require interaction?
    BOOL updaterAllowsInteraction = YES;
    if ([self.updaterDelegate respondsToSelector:@selector(updaterShouldAllowInstallerInteraction:)]) {
        updaterAllowsInteraction = [self.updaterDelegate updaterShouldAllowInstallerInteraction:self.updater];
    }
    return updaterAllowsInteraction;
}

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)updateItem
{
    if (self.resumingDownloadedUpdate) {
        [self.userDriver showDownloadedUpdateFoundWithAppcastItem:updateItem reply:^(SPUUpdateAlertChoice choice) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.host setObject:nil forUserDefaultsKey:SUSkippedVersionKey];
                switch (choice) {
                    case SPUInstallUpdateChoice:
                        [self.coreDriver extractDownloadedUpdate];
                        break;
                    case SPUSkipThisVersionChoice:
                        [self.coreDriver clearDownloadedUpdate];
                        [self.host setObject:[updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
                        // Fall through
                    case SPUInstallLaterChoice:
                        [self.delegate uiDriverIsRequestingAbortUpdateWithError:nil];
                        break;
                }
            });
        }];
    } else if (!self.resumingInstallingUpdate) {
        [self.userDriver showUpdateFoundWithAppcastItem:updateItem reply:^(SPUUpdateAlertChoice choice) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.host setObject:nil forUserDefaultsKey:SUSkippedVersionKey];
                switch (choice) {
                    case SPUInstallUpdateChoice:
                        [self.coreDriver downloadUpdateFromAppcastItem:updateItem];
                        break;
                    case SPUSkipThisVersionChoice:
                        [self.host setObject:[updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
                        // Fall through
                    case SPUInstallLaterChoice:
                        [self.delegate uiDriverIsRequestingAbortUpdateWithError:nil];
                        break;
                }
            });
        }];
    } else {
        [self.userDriver showResumableUpdateFoundWithAppcastItem:updateItem reply:^(SPUInstallUpdateStatus choice) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.host setObject:nil forUserDefaultsKey:SUSkippedVersionKey];
                [self.coreDriver finishInstallationWithResponse:choice displayingUserInterface:[self canDisplayInstallerUserInterface]];
            });
        }];
    }
    
    id <SPUUpdaterDelegate> updaterDelegate = self.updaterDelegate;
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
    [self.userDriver showDownloadInitiatedWithCompletion:^(SPUDownloadUpdateStatus downloadCompletionStatus) {
        switch (downloadCompletionStatus) {
            case SPUDownloadUpdateDone:
                break;
            case SPUDownloadUpdateCanceled:
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([self.updaterDelegate respondsToSelector:@selector(userDidCancelDownload:)]) {
                        [self.updaterDelegate userDidCancelDownload:self.updater];
                    }
                    
                    [self.delegate uiDriverIsRequestingAbortUpdateWithError:nil];
                });
                break;
        }
    }];
}

- (void)downloadDriverDidReceiveExpectedContentLength:(NSUInteger)expectedContentLength
{
    [self.userDriver showDownloadDidReceiveExpectedContentLength:expectedContentLength];
}

- (void)downloadDriverDidReceiveDataOfLength:(NSUInteger)length
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
        [self.userDriver showReadyToInstallAndRelaunch:^(SPUInstallUpdateStatus installUpdateStatus) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.coreDriver finishInstallationWithResponse:installUpdateStatus displayingUserInterface:[self canDisplayInstallerUserInterface]];
            });
        }];
    }
}

- (void)installerIsRequestingAppTermination
{
    [self.userDriver terminateApplication];
}

- (void)installerDidFinishInstallationWithAcknowledgement:(void(^)(void))acknowledgement
{
    [self.userDriver showUpdateInstallationDidFinishWithAcknowledgement:acknowledgement];
}

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    // A delegate may want to handle this type of error specially
    [self.delegate basicDriverIsRequestingAbortUpdateWithError:error];
}

- (void)coreDriverIsRequestingAbortUpdateWithError:(NSError *)error
{
    [self.delegate uiDriverIsRequestingAbortUpdateWithError:error];
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
            [self.userDriver showUpdateNotFoundWithAcknowledgement:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    abortUpdate();
                });
            }];
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
