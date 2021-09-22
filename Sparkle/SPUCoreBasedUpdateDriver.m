//
//  SPUCoreBasedUpdateDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUCoreBasedUpdateDriver.h"
#import "SUHost.h"
#import "SPUUpdaterDelegate.h"
#import "SPUBasicUpdateDriver.h"
#import "SPUInstallerDriver.h"
#import "SPUDownloadDriver.h"
#import "SULog.h"
#import "SUErrors.h"
#import "SPUResumableUpdate.h"
#import "SPUDownloadedUpdate.h"
#import "SPUInformationalUpdate.h"
#import "SUAppcastItem.h"
#import "SULocalizations.h"
#import "SPUInstallationType.h"
#import "SUPhasedUpdateGroupInfo.h"


#include "AppKitPrevention.h"

@interface SPUCoreBasedUpdateDriver () <SPUBasicUpdateDriverDelegate, SPUDownloadDriverDelegate, SPUInstallerDriverDelegate>

@property (nonatomic, readonly) SPUBasicUpdateDriver *basicDriver;
@property (nonatomic) SPUDownloadDriver *downloadDriver;
@property (nonatomic, readonly) SPUInstallerDriver *installerDriver;
@property (nonatomic, weak, readonly) id<SPUCoreBasedUpdateDriverDelegate> delegate;
@property (nonatomic) SUAppcastItem *updateItem;
@property (nonatomic, nullable) SUAppcastItem *secondaryUpdateItem;
@property (nonatomic) id<SPUResumableUpdate> resumableUpdate;
@property (nonatomic) SPUDownloadedUpdate *downloadedUpdateForRemoval;

@property (nonatomic, readonly) SUHost *host;
@property (nonatomic) BOOL resumingInstallingUpdate;
@property (nonatomic) BOOL silentInstall;
@property (nonatomic, readonly, weak) id updater; // if we didn't have legacy support, I'd remove this..
@property (nullable, nonatomic, readonly, weak) id <SPUUpdaterDelegate>updaterDelegate;
@property (nonatomic) NSString *userAgent;
@property (nonatomic, nullable) NSDictionary *httpHeaders;

@end

@implementation SPUCoreBasedUpdateDriver

@synthesize basicDriver = _basicDriver;
@synthesize downloadDriver = _downloadDriver;
@synthesize installerDriver = _installerDriver;
@synthesize delegate = _delegate;
@synthesize updateItem = _updateItem;
@synthesize secondaryUpdateItem = _secondaryUpdateItem;
@synthesize host = _host;
@synthesize resumingInstallingUpdate = _resumingInstallingUpdate;
@synthesize silentInstall = _silentInstall;
@synthesize updater = _updater;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize userAgent = _userAgent;
@synthesize httpHeaders = _httpHeaders;
@synthesize resumableUpdate = _resumableUpdate;
@synthesize downloadedUpdateForRemoval = _downloadedUpdateForRemoval;

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle updateCheck:(SPUUpdateCheck)updateCheck updater:(id)updater updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate delegate:(id<SPUCoreBasedUpdateDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
        
        NSString *bundleIdentifier = host.bundle.bundleIdentifier;
        assert(bundleIdentifier != nil);
        
        _basicDriver = [[SPUBasicUpdateDriver alloc] initWithHost:host updateCheck:updateCheck updater:updater updaterDelegate:updaterDelegate delegate:self];
        _installerDriver = [[SPUInstallerDriver alloc] initWithHost:host applicationBundle:applicationBundle updater:updater updaterDelegate:updaterDelegate delegate:self];
        
        _host = host;
        _updater = updater;
        _updaterDelegate = updaterDelegate;
    }
    return self;
}

- (void)setCompletionHandler:(SPUUpdateDriverCompletion)completionBlock
{
    [self.basicDriver setCompletionHandler:completionBlock];
}

- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(NSDictionary * _Nullable)httpHeaders inBackground:(BOOL)background requiresSilentInstall:(BOOL)silentInstall
{
    self.userAgent = userAgent;
    self.httpHeaders = httpHeaders;
    self.silentInstall = silentInstall;
    
    [self.basicDriver checkForUpdatesAtAppcastURL:appcastURL withUserAgent:userAgent httpHeaders:httpHeaders inBackground:background];
}

- (void)resumeInstallingUpdate
{
    self.resumingInstallingUpdate = YES;
    self.silentInstall = NO;
    
    [self.basicDriver resumeInstallingUpdate];
}

- (void)resumeUpdate:(id<SPUResumableUpdate>)resumableUpdate
{
    self.resumableUpdate = resumableUpdate;
    self.silentInstall = NO;
    
    [self.basicDriver resumeUpdate:resumableUpdate];
}

- (void)basicDriverDidFinishLoadingAppcast
{
    if ([self.delegate respondsToSelector:@selector(basicDriverDidFinishLoadingAppcast)]) {
        [self.delegate basicDriverDidFinishLoadingAppcast];
    }
}

- (void)basicDriverDidFindUpdateWithAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryUpdateItem systemDomain:(NSNumber * _Nullable)systemDomain
{
    self.updateItem = updateItem;
    self.secondaryUpdateItem = secondaryUpdateItem;
    
    if (self.resumingInstallingUpdate) {
        assert(systemDomain != nil);
        [self.installerDriver resumeInstallingUpdateWithUpdateItem:updateItem systemDomain:systemDomain.boolValue];
    }
    
    [self.delegate basicDriverDidFindUpdateWithAppcastItem:updateItem secondaryAppcastItem:secondaryUpdateItem];
}

- (void)downloadUpdateFromAppcastItem:(SUAppcastItem *)updateItem secondaryAppcastItem:(SUAppcastItem * _Nullable)secondaryUpdateItem inBackground:(BOOL)background
{
    self.downloadDriver = [[SPUDownloadDriver alloc] initWithUpdateItem:updateItem secondaryUpdateItem:secondaryUpdateItem host:self.host userAgent:self.userAgent httpHeaders:self.httpHeaders inBackground:background delegate:self];
    
    if ([self.updaterDelegate respondsToSelector:@selector((updater:willDownloadUpdate:withRequest:))]) {
        [self.updaterDelegate updater:self.updater
                               willDownloadUpdate:updateItem
                                      withRequest:self.downloadDriver.request];
    }
    
    [self.downloadDriver downloadFile];
}

- (void)downloadDriverWillBeginDownload
{
    if ([self.delegate respondsToSelector:@selector(downloadDriverWillBeginDownload)]) {
        [self.delegate downloadDriverWillBeginDownload];
    }
}

- (void)downloadDriverDidReceiveExpectedContentLength:(uint64_t)expectedContentLength
{
    if ([self.delegate respondsToSelector:@selector(downloadDriverDidReceiveExpectedContentLength:)]) {
        [self.delegate downloadDriverDidReceiveExpectedContentLength:expectedContentLength];
    }
}

- (void)downloadDriverDidReceiveDataOfLength:(uint64_t)length
{
    if ([self.delegate respondsToSelector:@selector(downloadDriverDidReceiveDataOfLength:)]) {
        [self.delegate downloadDriverDidReceiveDataOfLength:length];
    }
}

- (void)downloadDriverDidDownloadUpdate:(SPUDownloadedUpdate *)downloadedUpdate
{
    // Use a new update group for our next downloaded update
    // We could restrict this to when the appcast was downloaded in the background,
    // but it shouldn't matter.
    if (downloadedUpdate.updateItem.phasedRolloutInterval != nil) {
        [SUPhasedUpdateGroupInfo setNewUpdateGroupIdentifierForHost:self.host];
    }
    
    if ([self.updaterDelegate respondsToSelector:@selector(updater:didDownloadUpdate:)]) {
        [self.updaterDelegate updater:self.updater didDownloadUpdate:self.updateItem];
    }
    
    self.resumableUpdate = downloadedUpdate;
    [self extractUpdate:downloadedUpdate];
}

- (void)deferInformationalUpdate:(SUAppcastItem *)updateItem secondaryUpdate:(SUAppcastItem * _Nullable)secondaryUpdateItem
{
    self.resumableUpdate = [[SPUInformationalUpdate alloc] initWithAppcastItem:updateItem secondaryAppcastItem:secondaryUpdateItem];
}

- (void)extractDownloadedUpdate
{
    assert(self.resumableUpdate != nil);
    [self extractUpdate:self.resumableUpdate];
}

- (void)clearDownloadedUpdate
{
    id<NSObject> downloadedUpdateObject = (self.resumableUpdate != nil) ? self.resumableUpdate : self.downloadedUpdateForRemoval;
    assert(downloadedUpdateObject != nil);
    
    if (downloadedUpdateObject != nil && [downloadedUpdateObject isKindOfClass:[SPUDownloadedUpdate class]]) {
        if (self.downloadDriver == nil) {
            self.downloadDriver = [[SPUDownloadDriver alloc] initWithHost:self.host];
        }
        
        SPUDownloadedUpdate *downloadedUpdate = (SPUDownloadedUpdate *)downloadedUpdateObject;
        [self.downloadDriver removeDownloadedUpdate:downloadedUpdate];
    }
    
    // Clear any type of resumable update
    self.resumableUpdate = nil;
}

- (void)extractUpdate:(SPUDownloadedUpdate *)downloadedUpdate
{
    if ([self.updaterDelegate respondsToSelector:@selector(updater:willExtractUpdate:)]) {
        [self.updaterDelegate updater:self.updater willExtractUpdate:self.updateItem];
    }
    
    // Now we have to extract the downloaded archive.
    if ([self.delegate respondsToSelector:@selector(coreDriverDidStartExtractingUpdate)]) {
        [self.delegate coreDriverDidStartExtractingUpdate];
    }
    
    [self.installerDriver extractDownloadedUpdate:downloadedUpdate silently:self.silentInstall completion:^(NSError * _Nullable error) {
        if (error != nil) {
            if (error.code != SUInstallationAuthorizeLaterError) {
                [self clearDownloadedUpdate];
            }
            
            [self.delegate coreDriverIsRequestingAbortUpdateWithError:error];
        } else {
            // If the installer started properly, we can't use the downloaded update archive anymore
            // Especially if the installer fails later and we try resuming the update with a missing archive file
            // We must clear the download after the installer begins using it however (in -installerDidStartInstalling)
            self.downloadedUpdateForRemoval = downloadedUpdate;
            self.resumableUpdate = nil;
            
            if ([self.updaterDelegate respondsToSelector:@selector(updater:didExtractUpdate:)]) {
                [self.updaterDelegate updater:self.updater didExtractUpdate:self.updateItem];
            }
        }
    }];
}

- (void)downloadDriverDidFailToDownloadFileWithError:(NSError *)error
{
    if ([self.updaterDelegate respondsToSelector:@selector((updater:failedToDownloadUpdate:error:))]) {
        NSError *errorToReport = [error.userInfo objectForKey:NSUnderlyingErrorKey];
        if (errorToReport == nil) {
            errorToReport = error;
        }
        
        [self.updaterDelegate updater:self.updater
                           failedToDownloadUpdate:self.updateItem
                                            error:errorToReport];
    }
    
    [self.delegate coreDriverIsRequestingAbortUpdateWithError:error];
}

- (void)installerDidStartInstalling
{
    if ([self.delegate respondsToSelector:@selector(installerDidStartInstalling)]) {
        [self.delegate installerDidStartInstalling];
    }
}

- (void)installerDidStartExtracting
{
    // The installer has moved the archive and no longer needs the download directory
    [self clearDownloadedUpdate];
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

- (void)finishInstallationWithResponse:(SPUUserUpdateChoice)response displayingUserInterface:(BOOL)displayingUserInterface
{
    switch (response) {
        case SPUUserUpdateChoiceDismiss:
            [self.delegate coreDriverIsRequestingAbortUpdateWithError:nil];
            break;
        case SPUUserUpdateChoiceSkip:
            [self.installerDriver cancelUpdate];
            break;
        case SPUUserUpdateChoiceInstall:
            [self.installerDriver installWithToolAndRelaunch:YES displayingUserInterface:displayingUserInterface];
            break;
    }
}

- (void)installerWillFinishInstallationAndRelaunch:(BOOL)relaunch
{
    if ([self.updaterDelegate respondsToSelector:@selector((updater:willInstallUpdate:))]) {
        [self.updaterDelegate updater:self.updater willInstallUpdate:self.updateItem];
    }
    
    if (relaunch) {
        [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterWillRestartNotification object:self];
        if ([self.updaterDelegate respondsToSelector:@selector((updaterWillRelaunchApplication:))]) {
            [self.updaterDelegate updaterWillRelaunchApplication:self.updater];
        }
    }
}

- (void)installerDidFinishInstallationAndRelaunched:(BOOL)relaunched acknowledgement:(void(^)(void))acknowledgement
{
    if ([self.delegate respondsToSelector:@selector(installerDidFinishInstallationAndRelaunched:acknowledgement:)]) {
        [self.delegate installerDidFinishInstallationAndRelaunched:relaunched acknowledgement:acknowledgement];
    } else {
        acknowledgement();
    }
}

- (void)installerIsSendingAppTerminationSignal
{
    // If they don't respond or do anything, we'll just install after the user terminates the app anyway
    if ([self.delegate respondsToSelector:@selector(installerIsSendingAppTerminationSignal)]) {
        [self.delegate installerIsSendingAppTerminationSignal];
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
    SUAppcastItem *secondaryUpdateItem = self.secondaryUpdateItem;
    assert(secondaryUpdateItem != nil);
    
    BOOL backgroundDownload = self.downloadDriver.inBackground;
    
    [self clearDownloadedUpdate];
    
    // Fall back to the non-delta update. Note that we don't want to trigger another update was found event.
    self.updateItem = secondaryUpdateItem;
    self.secondaryUpdateItem = nil;
    
    [self downloadUpdateFromAppcastItem:secondaryUpdateItem secondaryAppcastItem:nil inBackground:backgroundDownload];
}

- (void)abortUpdateAndShowNextUpdateImmediately:(BOOL)shouldShowUpdateImmediately error:(nullable NSError *)error
{
    [self.installerDriver abortInstall];
    
    void (^basicDriverAbort)(void) = ^{
        id<SPUResumableUpdate> resumableUpdate = (error == nil || error.code == SUInstallationAuthorizeLaterError) ? self.resumableUpdate : nil;
        
        [self.basicDriver abortUpdateAndShowNextUpdateImmediately:shouldShowUpdateImmediately resumableUpdate:resumableUpdate error:error];
    };
    
    if (self.downloadDriver != nil) {
        [self.downloadDriver cleanup:^{
            basicDriverAbort();
        }];
    } else {
        basicDriverAbort();
    }
}

@end
