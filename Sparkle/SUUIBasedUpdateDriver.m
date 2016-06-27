//
//  SUUIBasedUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUIBasedUpdateDriver.h"
#import "SUCoreBasedUpdateDriver.h"
#import "SUUserDriver.h"
#import "SUHost.h"
#import "SUConstants.h"
#import "SUUpdaterDelegate.h"
#import "SUAppcastItem.h"
#import "SUErrors.h"
#import "SUURLDownload.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUUIBasedUpdateDriver() <SUCoreBasedUpdateDriverDelegate>

@property (nonatomic, readonly) SUCoreBasedUpdateDriver *coreDriver;
@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, readonly) BOOL allowsAutomaticUpdates;
@property (nonatomic, weak, readonly) id updater;
@property (weak, nonatomic, readonly) id<SUUpdaterDelegate> updaterDelegate;
@property (nonatomic, weak, readonly) id<SUUIBasedUpdateDriverDelegate> delegate;
@property (nonatomic, readonly) id<SUUserDriver> userDriver;
@property (nonatomic) BOOL resumingUpdate;

@end

@implementation SUUIBasedUpdateDriver

@synthesize coreDriver = _coreDriver;
@synthesize host = _host;
@synthesize allowsAutomaticUpdates = _allowsAutomaticUpdates;
@synthesize updater = _updater;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize userDriver = _userDriver;
@synthesize delegate = _delegate;
@synthesize resumingUpdate = _resumingUpdate;

- (instancetype)initWithHost:(SUHost *)host allowsAutomaticUpdates:(BOOL)allowsAutomaticUpdates sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater userDriver:(id <SUUserDriver>)userDriver updaterDelegate:(nullable id <SUUpdaterDelegate>)updaterDelegate delegate:(id<SUUIBasedUpdateDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _userDriver = userDriver;
        _delegate = delegate;
        _updater = updater;
        _updaterDelegate = updaterDelegate;
        _host = host;
        _allowsAutomaticUpdates = allowsAutomaticUpdates;
        
        _coreDriver = [[SUCoreBasedUpdateDriver alloc] initWithHost:host sparkleBundle:sparkleBundle updater:updater updaterDelegate:updaterDelegate delegate:self];
    }
    return self;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders includesSkippedUpdates:(BOOL)includesSkippedUpdates completion:(SUUpdateDriverCompletion)completionBlock
{
    [self.coreDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders includesSkippedUpdates:includesSkippedUpdates completion:completionBlock];
}

- (void)resumeUpdateWithCompletion:(SUUpdateDriverCompletion)completionBlock
{
    self.resumingUpdate = YES;
    [self.coreDriver resumeUpdateWithCompletion:completionBlock];
}

- (void)basicDriverDidFinishLoadingAppcast
{
    if ([self.delegate respondsToSelector:@selector(basicDriverDidFinishLoadingAppcast)]) {
        [self.delegate basicDriverDidFinishLoadingAppcast];
    }
}

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)updateItem
{
    if (!self.resumingUpdate) {
        [self.userDriver showUpdateFoundWithAppcastItem:updateItem allowsAutomaticUpdates:self.allowsAutomaticUpdates reply:^(SUUpdateAlertChoice choice) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.host setObject:nil forUserDefaultsKey:SUSkippedVersionKey];
                switch (choice) {
                    case SUInstallUpdateChoice:
                        [self.coreDriver downloadUpdateFromAppcastItem:updateItem];
                        break;
                    case SUSkipThisVersionChoice:
                        [self.host setObject:[updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
                        // Fall through
                    case SUInstallLaterChoice:
                        [self.delegate uiDriverIsRequestingAbortUpdateWithError:nil];
                        break;
                }
            });
        }];
    } else {
        [self.userDriver showResumableUpdateFoundWithAppcastItem:updateItem allowsAutomaticUpdates:self.allowsAutomaticUpdates reply:^(SUInstallUpdateStatus choice) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.host setObject:nil forUserDefaultsKey:SUSkippedVersionKey];
                [self.coreDriver finishInstallationWithResponse:choice];
            });
        }];
    }
    
    id <SUUpdaterDelegate> updaterDelegate = self.updaterDelegate;
    if (updateItem.releaseNotesURL != nil && (![updaterDelegate respondsToSelector:@selector(updaterShouldDownloadReleaseNotes:)] || [updaterDelegate updaterShouldDownloadReleaseNotes:self.updater])) {
        NSURLRequest *request = [NSURLRequest requestWithURL:updateItem.releaseNotesURL cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30];
        
        id <SUUserDriver> userDriver = self.userDriver;
        SUDownloadURLWithRequest(request, ^(NSData * _Nullable data, NSError * _Nullable error) {
            if (data != nil) {
                [userDriver showUpdateReleaseNotes:(NSData * _Nonnull)data];
            } else {
                [userDriver showUpdateReleaseNotesFailedToDownloadWithError:(NSError * _Nonnull)error];
            }
        });
    }
}

- (void)downloadDriverWillBeginDownload
{
    [self.userDriver showDownloadInitiatedWithCompletion:^(SUDownloadUpdateStatus downloadCompletionStatus) {
        switch (downloadCompletionStatus) {
            case SUDownloadUpdateDone:
                break;
            case SUDownloadUpdateCancelled:
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

- (void)coreDriverDidFinishDownloadingUpdate
{
    [self.userDriver showDownloadFinishedAndStartedExtractingUpdate];
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
        [self.userDriver showReadyToInstallAndRelaunch:^(SUInstallUpdateStatus installUpdateStatus) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.coreDriver finishInstallationWithResponse:installUpdateStatus];
            });
        }];
    }
}

- (void)installerIsRequestingAppTermination
{
    [self.userDriver terminateApplication];
}

- (void)installerDidFinishInstallation
{
    [self.userDriver showUpdateInstallationDidFinish];
}

- (BOOL)basicDriverShouldSignalShowingUpdateImmediately
{
    return NO;
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
        [self.coreDriver abortUpdateWithError:error];
    };
    
    if (error != nil) {
        NSError *nonNullError = error;
        
        if (error.code == SUNoUpdateError) {
            [self.userDriver showUpdateNotFoundWithAcknowledgement:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    abortUpdate();
                });
            }];
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
