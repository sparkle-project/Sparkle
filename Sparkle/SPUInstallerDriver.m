//
//  SPUInstallerDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUInstallerDriver.h"
#import "SULog.h"
#import "SPUMessageTypes.h"
#import "SPUXPCServiceInfo.h"
#import "SPUUpdaterDelegate.h"
#import "SUAppcastItem.h"
#import "SULog.h"
#import "SULocalizations.h"
#import "SUErrors.h"
#import "SUHost.h"
#import "SUFileManager.h"
#import "SPUSecureCoding.h"
#import "SPUInstallationInputData.h"
#import "SUInstallerLauncher.h"
#import "SUInstallerConnection.h"
#import "SUInstallerConnectionProtocol.h"
#import "SUXPCInstallerConnection.h"
#import "SPUDownloadedUpdate.h"
#import "SPUInstallationType.h"


#include "AppKitPrevention.h"

#define FIRST_INSTALLER_MESSAGE_TIMEOUT 7ull

@interface NSObject (PrivateDelegateMethods)

- (nullable NSString *)_pathToRelaunchForUpdater:(SPUUpdater *)updater;

@end

@interface SPUInstallerDriver () <SUInstallerCommunicationProtocol>

@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, readonly) NSBundle *applicationBundle;
@property (nonatomic, readonly) NSBundle *sparkleBundle;
@property (nonatomic, weak, readonly) id<SPUInstallerDriverDelegate> delegate;
@property (nonatomic) SPUInstallerMessageType currentStage;
@property (nonatomic) BOOL startedInstalling;

@property (nonatomic) id<SUInstallerConnectionProtocol> installerConnection;

@property (nonatomic) NSUInteger extractionAttempts;
@property (nonatomic) BOOL postponedOnce;
@property (nonatomic, weak, readonly) id updater;
@property (nonatomic, weak, readonly) id<SPUUpdaterDelegate> updaterDelegate;
@property (nonatomic) BOOL willRelaunch;

@property (nonatomic) BOOL systemDomain;

@property (nonatomic) SUAppcastItem *updateItem;
@property (nonatomic, copy) NSString *downloadName;
@property (nonatomic, copy) NSString *temporaryDirectory;

@property (nonatomic) BOOL aborted;
@property (nonatomic, nullable) NSError *installerError;

@end

@implementation SPUInstallerDriver

@synthesize host = _host;
@synthesize applicationBundle = _applicationBundle;
@synthesize sparkleBundle = _sparkleBundle;
@synthesize delegate = _delegate;
@synthesize currentStage = _currentStage;
@synthesize startedInstalling = _startedInstalling;
@synthesize installerConnection = _installerConnection;
@synthesize extractionAttempts = _extractionAttempts;
@synthesize postponedOnce = _postponedOnce;
@synthesize updater = _updater;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize willRelaunch = _willRelaunch;
@synthesize systemDomain = _systemDomain;
@synthesize updateItem = _updateItem;
@synthesize downloadName = _downloadName;
@synthesize temporaryDirectory = _temporaryDirectory;
@synthesize aborted = _aborted;
@synthesize installerError = _installerError;

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater updaterDelegate:(id<SPUUpdaterDelegate>)updaterDelegate delegate:(nullable id<SPUInstallerDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _host = host;
        _applicationBundle = applicationBundle;
        _sparkleBundle = sparkleBundle;
        _updater = updater;
        _updaterDelegate = updaterDelegate;
        _delegate = delegate;
    }
    return self;
}

- (void)setUpConnection
{
    if (self.installerConnection != nil) {
        return;
    }
    
    NSString *hostBundleIdentifier = self.host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    
    if (!SPUXPCServiceExists(@INSTALLER_CONNECTION_BUNDLE_ID)) {
        self.installerConnection = [[SUInstallerConnection alloc] initWithDelegate:self];
    } else {
        self.installerConnection = [[SUXPCInstallerConnection alloc] initWithDelegate:self];
    }
    
    __weak SPUInstallerDriver *weakSelf = self;
    [self.installerConnection setInvalidationHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            SPUInstallerDriver *strongSelf = weakSelf;
            if (strongSelf.installerConnection != nil && !strongSelf.aborted) {
                
                NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{
                    NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while running the updater. Please try again later.", nil),
                    NSLocalizedFailureReasonErrorKey:@"The remote port connection was invalidated from the updater. For additional details, please check Console logs for "@SPARKLE_RELAUNCH_TOOL_NAME
                }];
                
                NSError *installerError = strongSelf.installerError;
                if (installerError != nil) {
                    userInfo[NSUnderlyingErrorKey] = installerError;
                }
                
                [strongSelf.delegate installerIsRequestingAbortInstallWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:userInfo]];
            }
        });
    }];
    
    NSString *serviceName = SPUInstallerServiceNameForBundleIdentifier(hostBundleIdentifier);
    NSString *installationType = self.updateItem.installationType;
    assert(installationType != nil);
    
    [self.installerConnection setServiceName:serviceName systemDomain:self.systemDomain];
    
    [self sendInstallationData];
}

// This can be called multiple times (eg: if a delta update fails, this may be called again with a regular update item)
- (void)extractDownloadedUpdate:(SPUDownloadedUpdate *)downloadedUpdate silently:(BOOL)silently preventsInstallerInteraction:(BOOL)preventsInstallerInteraction completion:(void (^)(NSError * _Nullable))completionHandler
{
    self.updateItem = downloadedUpdate.updateItem;
    self.temporaryDirectory = downloadedUpdate.temporaryDirectory;
    self.downloadName = downloadedUpdate.downloadName;
    
    self.currentStage = SPUInstallerNotStarted;
    
    if (self.installerConnection == nil) {
        [self launchAutoUpdateSilently:silently preventsInstallerInteraction:preventsInstallerInteraction completion:completionHandler];
    } else {
        // The Install tool is already alive; just send out installation input data again
        [self sendInstallationData];
        completionHandler(nil);
    }
}

- (void)resumeInstallingUpdateWithUpdateItem:(SUAppcastItem *)updateItem systemDomain:(BOOL)systemDomain
{
    self.updateItem = updateItem;
    self.systemDomain = systemDomain;
}

- (void)sendInstallationData
{
    NSString *pathToRelaunch = self.applicationBundle.bundlePath;
    // Give the delegate one more chance for determining the path to relaunch via a private API used by SUUpdater
    if ([self.updaterDelegate respondsToSelector:@selector(_pathToRelaunchForUpdater:)]) {
        NSString *relaunchPath = [(NSObject *)self.updaterDelegate _pathToRelaunchForUpdater:self.updater];
        if (relaunchPath != nil) {
            pathToRelaunch = relaunchPath;
        }
    }

    NSString *decryptionPassword = nil;
    if ([self.updaterDelegate respondsToSelector:@selector(decryptionPasswordForUpdater:)]) {
        decryptionPassword = [self.updaterDelegate decryptionPasswordForUpdater:self.updater];
    }
    
    SPUInstallationInputData *installationData = [[SPUInstallationInputData alloc] initWithRelaunchPath:pathToRelaunch hostBundlePath:self.host.bundlePath updateDirectoryPath:self.temporaryDirectory downloadName:self.downloadName installationType:self.updateItem.installationType signatures:self.updateItem.signatures decryptionPassword:decryptionPassword];
    
    NSData *archivedData = SPUArchiveRootObjectSecurely(installationData);
    if (archivedData == nil) {
        [self.delegate installerIsRequestingAbortInstallWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey:SULocalizedString(@"An error occurred while encoding the installer parameters. Please try again later.", nil) }]];
        return;
    }
    
    [self.installerConnection handleMessageWithIdentifier:SPUInstallationData data:archivedData];
    
    self.currentStage = SPUInstallerNotStarted;
    
    // If the number of extractions attempts stays the same, then we've waited too long and should abort the installation
    // The extraction attempts is incremented when we receive an extraction should start message from the installer
    // This also handles the case when a delta extraction fails and tries to re-try another extraction attempt later
    // We will also want to make sure current stage is still SUInstallerNotStarted because it may not be due to resumability
    NSUInteger currentExtractionAttempts = self.extractionAttempts;
    __weak SPUInstallerDriver *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(FIRST_INSTALLER_MESSAGE_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SPUInstallerDriver *strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf.currentStage == SPUInstallerNotStarted && currentExtractionAttempts == self.extractionAttempts) {
            SULog(SULogLevelError, @"Timeout: Installer never started archive extraction");
            [strongSelf.delegate installerIsRequestingAbortInstallWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey:SULocalizedString(@"An error occurred while starting the installer. Please try again later.", nil) }]];
        }
    });
}

- (void)handleMessageWithIdentifier:(int32_t)identifier data:(NSData *)data
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _handleMessageWithIdentifier:identifier data:data];
    });
}

- (void)_handleMessageWithIdentifier:(int32_t)identifier data:(NSData *)data
{
    if (!SPUInstallerMessageTypeIsLegal(self.currentStage, identifier)) {
        SULog(SULogLevelError, @"Error: received out of order message with current stage: %d, requested stage: %d", self.currentStage, identifier);
        return;
    }
    
    if (identifier == SPUExtractionStarted) {
        self.extractionAttempts++;
        self.currentStage = identifier;
    } else if (identifier == SPUExtractedArchiveWithProgress) {
        if (data.length == sizeof(double) && sizeof(double) == sizeof(uint64_t)) {
            uint64_t progressValue = CFSwapInt64LittleToHost(*(const uint64_t *)data.bytes);
            double progress = *(double *)&progressValue;
            [self.delegate installerDidExtractUpdateWithProgress:progress];
            self.currentStage = identifier;
        }
    } else if (identifier == SPUArchiveExtractionFailed) {
        // If this is a delta update, there must be a regular update we can fall back to
        if ([self.updateItem isDeltaUpdate]) {
            [self.delegate installerDidFailToApplyDeltaUpdate];
        } else {
            // Don't have to store current stage because we're going to abort
            NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{ NSLocalizedDescriptionKey:SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil) }];
            
            NSError *unarchivedError = (NSError *)SPUUnarchiveRootObjectSecurely(data, [NSError class]);
            if (unarchivedError != nil) {
                userInfo[NSUnderlyingErrorKey] = unarchivedError;
            }
            
            [self.delegate installerIsRequestingAbortInstallWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:userInfo]];
        }
    } else if (identifier == SPUValidationStarted) {
        self.currentStage = identifier;
    } else if (identifier == SPUInstallationStartedStage1) {
        self.currentStage = identifier;
        [self.delegate installerDidStartInstalling];
        self.startedInstalling = YES;
        
    } else if (identifier == SPUInstallationFinishedStage1) {
        self.currentStage = identifier;
        
        // Let the installer keep a copy of the appcast item data
        // We may want to ask for it later (note the updater can relaunch without the app necessarily having relaunched)
        NSData *updateItemData = SPUArchiveRootObjectSecurely(self.updateItem);
        
        if (updateItemData != nil) {
            [self.installerConnection handleMessageWithIdentifier:SPUSentUpdateAppcastItemData data:updateItemData];
        } else {
            SULog(SULogLevelError, @"Error: Archived data to send for appcast item is nil");
        }
        
        BOOL canInstallSilently = NO;
        if (data.length >= sizeof(uint8_t)) {
            canInstallSilently = (BOOL)*(const uint8_t *)data.bytes;
        }
        
        BOOL hasTargetTerminated = NO;
        if (data.length >= sizeof(uint8_t) * 2) {
            hasTargetTerminated = (BOOL)*((const uint8_t *)data.bytes + 1);
        }
        
        [self.delegate installerDidFinishPreparationAndWillInstallImmediately:hasTargetTerminated silently:canInstallSilently];
    } else if (identifier == SPUInstallationFinishedStage2) {
        self.currentStage = identifier;
        
        if (!self.startedInstalling) {
            // It's possible we can start from resuming to stage 2 rather than doing stage 1 again, so we should notify to start installing if we haven't done so already
            self.startedInstalling = YES;
            [self.delegate installerDidStartInstalling];
        }
        
        BOOL hasTargetTerminated = NO;
        if (data.length >= sizeof(uint8_t)) {
            hasTargetTerminated = (BOOL)*((const uint8_t *)data.bytes);
        }
        
        [self.delegate installerWillFinishInstallationAndRelaunch:self.willRelaunch];
        
        if (!hasTargetTerminated) {
            [self.delegate installerIsSendingAppTerminationSignal];
        }
    } else if (identifier == SPUInstallationFinishedStage3) {
        self.currentStage = identifier;
        
        [self.installerConnection invalidate];
        self.installerConnection = nil;
        
        [self.delegate installerDidFinishInstallationWithAcknowledgement:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate installerIsRequestingAbortInstallWithError:nil];
            });
        }];
    } else if (identifier == SPUUpdaterAlivePing) {
        // Don't update the current stage; a ping request has no effect on that.
        [self.installerConnection handleMessageWithIdentifier:SPUUpdaterAlivePong data:[NSData data]];
    } else if (identifier == SPUInstallerError) {
        // Don't update the current stage; an installation error has no effect on that.
        self.installerError = (NSError *)SPUUnarchiveRootObjectSecurely(data, [NSError class]);
    }
}

- (void)checkIfApplicationInstallationRequiresAuthorizationWithReply:(void (^)(BOOL requiresAuthorization))reply
{
    id<SUInstallerLauncherProtocol> installerLauncher = nil;
    __block BOOL madeReply = NO;
    NSXPCConnection *launcherConnection = nil;
    
    if (!SPUXPCServiceExists(@INSTALLER_LAUNCHER_BUNDLE_ID)) {
        installerLauncher = [[SUInstallerLauncher alloc] init];
    } else {
        launcherConnection = [[NSXPCConnection alloc] initWithServiceName:@INSTALLER_LAUNCHER_BUNDLE_ID];
        launcherConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerLauncherProtocol)];
        
        launcherConnection.interruptionHandler = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!madeReply) {
                    // We'll break the retain cycle in the invalidation handler
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
                    [launcherConnection invalidate];
#pragma clang diagnostic pop
                }
            });
        };
        
        launcherConnection.invalidationHandler = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!madeReply) {
                    // If something went horribly wrong, just guess that we won't require authorization
                    reply(NO);
                    
                    // Break the retain cycle
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
                    launcherConnection.interruptionHandler = nil;
                    launcherConnection.invalidationHandler = nil;
#pragma clang diagnostic pop
                }
            });
        };
        
        [launcherConnection resume];
        
        installerLauncher = launcherConnection.remoteObjectProxy;
    }
    
    [installerLauncher checkIfApplicationInstallationRequiresAuthorizationWithHostBundlePath:self.host.bundlePath reply:^(BOOL requiresAuthorization) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!madeReply) {
                madeReply = YES;
                [launcherConnection invalidate];
                
                reply(requiresAuthorization);
            }
        });
    }];
}

- (void)launchAutoUpdateSilently:(BOOL)silently preventsInstallerInteraction:(BOOL)preventsInstallerInteraction completion:(void (^)(NSError *_Nullable))completionHandler
{
    id<SUInstallerLauncherProtocol> installerLauncher = nil;
    __block BOOL retrievedLaunchStatus = NO;
    NSXPCConnection *launcherConnection = nil;
    
    if (!SPUXPCServiceExists(@INSTALLER_LAUNCHER_BUNDLE_ID)) {
        installerLauncher = [[SUInstallerLauncher alloc] init];
    } else {
        launcherConnection = [[NSXPCConnection alloc] initWithServiceName:@INSTALLER_LAUNCHER_BUNDLE_ID];
        launcherConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerLauncherProtocol)];
        
        launcherConnection.interruptionHandler = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!retrievedLaunchStatus) {
                    // We'll break the retain cycle in the invalidation handler
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
                    [launcherConnection invalidate];
#pragma clang diagnostic pop
                }
            });
        };
        
        launcherConnection.invalidationHandler = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!retrievedLaunchStatus) {
                    NSError *error =
                    [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey:SULocalizedString(@"An error occurred while connecting to the installer. Please try again later.", nil) }];
                    
                    completionHandler(error);
                    
                    // Break the retain cycle
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-retain-cycles"
                    launcherConnection.interruptionHandler = nil;
                    launcherConnection.invalidationHandler = nil;
#pragma clang diagnostic pop
                }
            });
        };
        
        [launcherConnection resume];
        
        installerLauncher = launcherConnection.remoteObjectProxy;
    }
    
    // Our driver (automatic or UI based) has a say if interaction is allowed as well
    // An automatic driver may disallow interaction but the updater could try again later for a UI based driver that does allow interaction
    BOOL driverAllowsInteraction = !silently;
    
    NSString *hostBundlePath = self.host.bundle.bundlePath;
    assert(hostBundlePath != nil);
    
    NSString *installationType = self.updateItem.installationType;
    assert(installationType != nil);
    
    // The installer launcher could be in a XPC service, so we don't want to do localization in there
    NSString *authorizationPrompt = [NSString stringWithFormat:SULocalizedString(@"%1$@ wants to update.", nil), self.host.name];
    [installerLauncher launchInstallerWithHostBundlePath:hostBundlePath authorizationPrompt:authorizationPrompt installationType:installationType allowingDriverInteraction:driverAllowsInteraction allowingUpdaterInteraction:!preventsInstallerInteraction completion:^(SUInstallerLauncherStatus result, BOOL systemDomain) {
        dispatch_async(dispatch_get_main_queue(), ^{
            retrievedLaunchStatus = YES;
            [launcherConnection invalidate];
            
            switch (result) {
                case SUInstallerLauncherFailure:
                    SULog(SULogLevelError, @"Error: Failed to gain authorization required to update target");
                    completionHandler([NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey:SULocalizedString(@"An error occurred while launching the installer. Please try again later.", nil) }]);
                    break;
                case SUInstallerLauncherCanceled:
                    completionHandler([NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationCanceledError userInfo:nil]);
                    break;
                case SUInstallerLauncherAuthorizeLater:
                    completionHandler([NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationAuthorizeLaterError userInfo:nil]);
                    break;
                case SUInstallerLauncherSuccess:
                    self.systemDomain = systemDomain;
                    [self setUpConnection];
                    completionHandler(nil);
                    break;
            }
        });
    }];
}

- (BOOL)mayUpdateAndRestart
{
    return (!self.updaterDelegate || ![self.updaterDelegate respondsToSelector:@selector((updaterShouldRelaunchApplication:))] || [self.updaterDelegate updaterShouldRelaunchApplication:self.updater]);
}

- (void)installWithToolAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI
{
    assert(self.updateItem);
    
    if (![self mayUpdateAndRestart])
    {
        [self.delegate installerIsRequestingAbortInstallWithError:nil];
        return;
    }
    
    // Give the host app an opportunity to postpone the install and relaunch.
    if (!self.postponedOnce)
    {
        if ([self.updaterDelegate respondsToSelector:@selector(updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)]) {
            self.postponedOnce = YES;
            __weak SPUInstallerDriver *weakSelf = self;
            if ([self.updaterDelegate updater:self.updater shouldPostponeRelaunchForUpdate:self.updateItem untilInvokingBlock:^{
                [weakSelf installWithToolAndRelaunch:relaunch displayingUserInterface:showUI];
            }]) {
                return;
            }
        }
    }
    
    // Set up connection to the installer if one is not set up already
    [self setUpConnection];
    
    // For resumability, we'll assume we are far enough for the installation to continue
    self.currentStage = SPUInstallationFinishedStage1;
    
    self.willRelaunch = relaunch;
    
    uint8_t response[2] = {(uint8_t)relaunch, (uint8_t)showUI};
    NSData *responseData = [NSData dataWithBytes:response length:sizeof(response)];
    
    [self.installerConnection handleMessageWithIdentifier:SPUResumeInstallationToStage2 data:responseData];
    
    // the installer will send us SPUInstallationFinishedStage2 when stage 2 is done
}

- (void)abortInstall
{
    self.aborted = YES;
    if (self.installerConnection != nil) {
        [self.installerConnection invalidate];
        self.installerConnection = nil;
    }
}

@end
