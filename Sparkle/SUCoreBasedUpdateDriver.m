//
//  SUCoreBasedUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUCoreBasedUpdateDriver.h"
#import "SUHost.h"
#import "SUUpdaterDelegate.h"
#import "SUBasicUpdateDriver.h"
#import "SUInstallerDriver.h"
#import "SUDownloadDriver.h"
#import "SULog.h"
#import "SUErrors.h"
#import "SUDownloadedUpdate.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUCoreBasedUpdateDriver () <SUBasicUpdateDriverDelegate, SUDownloadDriverDelegate, SUInstallerDriverDelegate>

@property (nonatomic, readonly) SUBasicUpdateDriver *basicDriver;
@property (nonatomic) SUDownloadDriver *downloadDriver;
@property (nonatomic, readonly) SUInstallerDriver *installerDriver;
@property (nonatomic, weak, readonly) id<SUCoreBasedUpdateDriverDelegate> delegate;
@property (nonatomic) SUAppcastItem *updateItem;
@property (nonatomic) SUDownloadedUpdate *downloadedUpdate;

@property (nonatomic, readonly) SUHost *host;
@property (nonatomic) BOOL resumingInstallingUpdate;
@property (nonatomic) BOOL silentInstall;
@property (nonatomic, readonly, weak) id updater; // if we didn't have legacy support, I'd remove this..
@property (nullable, nonatomic, readonly, weak) id <SUUpdaterDelegate>updaterDelegate;
@property (nonatomic) NSString *userAgent;

@end

@implementation SUCoreBasedUpdateDriver

@synthesize basicDriver = _basicDriver;
@synthesize downloadDriver = _downloadDriver;
@synthesize installerDriver = _installerDriver;
@synthesize delegate = _delegate;
@synthesize updateItem = _updateItem;
@synthesize host = _host;
@synthesize resumingInstallingUpdate = _resumingInstallingUpdate;
@synthesize silentInstall = _silentInstall;
@synthesize updater = _updater;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize userAgent = _userAgent;
@synthesize downloadedUpdate = _downloadedUpdate;

- (instancetype)initWithHost:(SUHost *)host sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater updaterDelegate:(nullable id <SUUpdaterDelegate>)updaterDelegate delegate:(id<SUCoreBasedUpdateDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
        
        NSString *bundleIdentifier = host.bundle.bundleIdentifier;
        assert(bundleIdentifier != nil);
        
        _basicDriver = [[SUBasicUpdateDriver alloc] initWithHost:host updater:updater updaterDelegate:updaterDelegate delegate:self];
        _installerDriver = [[SUInstallerDriver alloc] initWithHost:host sparkleBundle:sparkleBundle updater:updater updaterDelegate:updaterDelegate delegate:self];
        
        _host = host;
        _updater = updater;
        _updaterDelegate = updaterDelegate;
    }
    return self;
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary *)httpHeaders includesSkippedUpdates:(BOOL)includesSkippedUpdates requiresSilentInstall:(BOOL)silentInstall completion:(SUUpdateDriverCompletion)completionBlock
{
    self.userAgent = userAgent;
    self.silentInstall = silentInstall;
    
    [self.basicDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders includesSkippedUpdates:includesSkippedUpdates completion:completionBlock];
}

- (void)resumeInstallingUpdateWithCompletion:(SUUpdateDriverCompletion)completionBlock
{
    self.resumingInstallingUpdate = YES;
    self.silentInstall = NO;
    
    [self.basicDriver resumeInstallingUpdateWithCompletion:completionBlock];
}

- (void)resumeDownloadedUpdate:(SUDownloadedUpdate *)downloadedUpdate completion:(SUUpdateDriverCompletion)completionBlock
{
    self.downloadedUpdate = downloadedUpdate;
    self.silentInstall = NO;
    
    [self.basicDriver resumeDownloadedUpdate:downloadedUpdate completion:completionBlock];
}

- (void)basicDriverDidFinishLoadingAppcast
{
    if ([self.delegate respondsToSelector:@selector(basicDriverDidFinishLoadingAppcast)]) {
        [self.delegate basicDriverDidFinishLoadingAppcast];
    }
}

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)updateItem
{
    self.updateItem = updateItem;
    
    if (self.resumingInstallingUpdate) {
        [self.installerDriver resumeInstallingUpdateWithUpdateItem:updateItem];
    }
    
    [self.delegate basicDriverDidFindUpdateWithAppcastItem:updateItem];
}

- (void)downloadUpdateFromAppcastItem:(SUAppcastItem *)updateItem
{
    self.downloadDriver = [[SUDownloadDriver alloc] initWithUpdateItem:updateItem host:self.host userAgent:self.userAgent delegate:self];
    
    if ([self.updaterDelegate respondsToSelector:@selector(updater:willDownloadUpdate:withRequest:)]) {
        [self.updaterDelegate updater:self.updater
                               willDownloadUpdate:updateItem
                                      withRequest:self.downloadDriver.request];
    }
    
    [self.downloadDriver downloadUpdate];
}

- (void)downloadDriverWillBeginDownload
{
    if ([self.delegate respondsToSelector:@selector(downloadDriverWillBeginDownload)]) {
        [self.delegate downloadDriverWillBeginDownload];
    }
}

- (void)downloadDriverDidReceiveExpectedContentLength:(NSUInteger)expectedContentLength
{
    if ([self.delegate respondsToSelector:@selector(downloadDriverDidReceiveExpectedContentLength:)]) {
        [self.delegate downloadDriverDidReceiveExpectedContentLength:expectedContentLength];
    }
}

- (void)downloadDriverDidReceiveDataOfLength:(NSUInteger)length
{
    if ([self.delegate respondsToSelector:@selector(downloadDriverDidReceiveDataOfLength:)]) {
        [self.delegate downloadDriverDidReceiveDataOfLength:length];
    }
}

- (void)downloadDriverDidDownloadUpdate:(SUDownloadedUpdate *)downloadedUpdate
{
    self.downloadedUpdate = downloadedUpdate;
    [self extractUpdate:downloadedUpdate];
}

- (void)extractDownloadedUpdate
{
    assert(self.downloadedUpdate != nil);
    [self extractUpdate:self.downloadedUpdate];
}

- (void)clearDownloadedUpdate
{
    self.downloadedUpdate = nil;
}

- (void)extractUpdate:(SUDownloadedUpdate *)downloadedUpdate
{
    // Now we have to extract the downloaded archive.
    if ([self.delegate respondsToSelector:@selector(coreDriverDidStartExtractingUpdate)]) {
        [self.delegate coreDriverDidStartExtractingUpdate];
    }
    
    [self.installerDriver extractDownloadedUpdate:downloadedUpdate silently:self.silentInstall completion:^(NSError * _Nullable error) {
        if (error != nil) {
            [self.delegate coreDriverIsRequestingAbortUpdateWithError:error];
        } else {
            // If the installer started properly, we can't use the downloaded update archive anymore
            // Especially if the installer fails later and we try resuming the update with a missing archive file
            [self clearDownloadedUpdate];
        }
    }];
}

- (void)downloadDriverDidFailToDownloadUpdateWithError:(NSError *)error
{
    if ([self.updaterDelegate respondsToSelector:@selector(updater:failedToDownloadUpdate:error:)]) {
        [self.updaterDelegate updater:self.updater
                           failedToDownloadUpdate:self.updateItem
                                            error:error.userInfo[NSUnderlyingErrorKey]];
    }
    
    [self.delegate coreDriverIsRequestingAbortUpdateWithError:error];
}

- (void)installerDidStartInstalling
{
    if ([self.delegate respondsToSelector:@selector(installerDidStartInstalling)]) {
        [self.delegate installerDidStartInstalling];
    }
}

- (void)installerDidExtractUpdateWithProgress:(double)progress
{
    if ([self.delegate respondsToSelector:@selector(installerDidExtractUpdateWithProgress:)]) {
        [self.delegate installerDidExtractUpdateWithProgress:progress];
    }
}

- (void)installerDidFinishPreparationAndWillInstallImmediately:(BOOL)willInstallImmediately silently:(BOOL)willInstallSilently
{
    [self.delegate installerDidFinishPreparationAndWillInstallImmediately:willInstallImmediately silently:willInstallSilently];
}

- (void)finishInstallationWithResponse:(SPUInstallUpdateStatus)installUpdateStatus displayingUserInterface:(BOOL)displayingUserInterface
{
    switch (installUpdateStatus) {
        case SPUDismissUpdateInstallation:
            [self.delegate coreDriverIsRequestingAbortUpdateWithError:nil];
            break;
        case SPUInstallUpdateNow:
            [self.installerDriver installWithToolAndRelaunch:NO displayingUserInterface:displayingUserInterface];
            break;
        case SPUInstallAndRelaunchUpdateNow:
            [self.installerDriver installWithToolAndRelaunch:YES displayingUserInterface:displayingUserInterface];
            break;
    }
}

- (void)installerWillFinishInstallationAndRelaunch:(BOOL)relaunch
{
    if ([self.updaterDelegate respondsToSelector:@selector(updater:willInstallUpdate:)]) {
        [self.updaterDelegate updater:self.updater willInstallUpdate:self.updateItem];
    }
    
    if (relaunch) {
        [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterWillRestartNotification object:self];
        if ([self.updaterDelegate respondsToSelector:@selector(updaterWillRelaunchApplication:)]) {
            [self.updaterDelegate updaterWillRelaunchApplication:self.updater];
        }
    }
}

- (void)installerDidFinishInstallation
{
    if ([self.delegate respondsToSelector:@selector(installerDidFinishInstallation)]) {
        [self.delegate installerDidFinishInstallation];
    }
}

- (void)installerIsRequestingAppTermination
{
    // If they don't respond or do anything, we'll just install after the user terminates the app anyway
    if ([self.delegate respondsToSelector:@selector(installerIsRequestingAppTermination)]) {
        [self.delegate installerIsRequestingAppTermination];
    }
}

- (void)installerIsRequestingAbortInstallWithError:(nullable NSError *)error
{
    [self.delegate coreDriverIsRequestingAbortUpdateWithError:error];
}

- (void)basicDriverIsRequestingAbortUpdateWithError:(nullable NSError *)error
{
    // A delegate may want to handle this type of error specially
    [self.delegate basicDriverIsRequestingAbortUpdateWithError:error];
}

- (void)installerDidFailToApplyDeltaUpdate
{
    SUAppcastItem *nonDeltaUpdateItem = self.basicDriver.nonDeltaUpdateItem;
    assert(nonDeltaUpdateItem != nil);
    
    [self clearDownloadedUpdate];
    
    // Fall back to the non-delta update. Note that we don't want to trigger another update was found event.
    self.updateItem = nonDeltaUpdateItem;
    [self downloadUpdateFromAppcastItem:nonDeltaUpdateItem];
}

- (void)abortUpdateAndShowNextUpdateImmediately:(BOOL)shouldShowUpdateImmediately error:(nullable NSError *)error
{
    [self.installerDriver abortInstall];
    [self.downloadDriver cleanup];
    
    SUDownloadedUpdate *downloadedUpdate = (error == nil || error.code == SUInstallationAuthorizeLaterError) ? self.downloadedUpdate : nil;
    [self.basicDriver abortUpdateAndShowNextUpdateImmediately:shouldShowUpdateImmediately downloadedUpdate:downloadedUpdate error:error];
}

@end
