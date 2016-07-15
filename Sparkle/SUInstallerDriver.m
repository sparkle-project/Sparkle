//
//  SUInstallerDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUInstallerDriver.h"
#import "SULog.h"
#import "SUMessageTypes.h"
#import "SUXPCServiceInfo.h"
#import "SUUpdaterDelegate.h"
#import "SUAppcastItem.h"
#import "SULog.h"
#import "SULocalizations.h"
#import "SUErrors.h"
#import "SUHost.h"
#import "SUFileManager.h"
#import "SUSecureCoding.h"
#import "SUInstallationInputData.h"
#import "SUInstallerLauncher.h"
#import "SUXPCServiceInfo.h"
#import "SUInstallerConnection.h"
#import "SUInstallerConnectionProtocol.h"
#import "SUXPCInstallerConnection.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

#define FIRST_INSTALLER_MESSAGE_TIMEOUT 7ull

@interface SUInstallerDriver () <SUInstallerCommunicationProtocol>

@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, readonly, copy) NSString *cachePath;
@property (nonatomic, readonly) NSBundle *sparkleBundle;
@property (nonatomic, weak, readonly) id<SUInstallerDriverDelegate> delegate;
@property (nonatomic) SUInstallerMessageType currentStage;
@property (nonatomic) BOOL startedInstalling;

@property (nonatomic) id<SUInstallerConnectionProtocol> installerConnection;

@property (nonatomic) NSUInteger extractionAttempts;
@property (nonatomic) BOOL postponedOnce;
@property (nonatomic, weak, readonly) id updater;
@property (nonatomic, weak, readonly) id<SUUpdaterDelegate> updaterDelegate;
@property (nonatomic) BOOL willRelaunch;

@property (nonatomic) SUAppcastItem *updateItem;
@property (nonatomic, copy) NSString *downloadName;
@property (nonatomic, copy) NSString *temporaryDirectory;

@end

@implementation SUInstallerDriver

@synthesize host = _host;
@synthesize cachePath = _cachePath;
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
@synthesize updateItem = _updateItem;
@synthesize downloadName = _downloadName;
@synthesize temporaryDirectory = _temporaryDirectory;

- (instancetype)initWithHost:(SUHost *)host cachePath:(NSString *)cachePath sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater updaterDelegate:(id<SUUpdaterDelegate>)updaterDelegate delegate:(nullable id<SUInstallerDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _host = host;
        _cachePath = [cachePath copy];
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
    
    if (!SUXPCServiceExists(@INSTALLER_CONNECTION_PRODUCT_NAME)) {
        self.installerConnection = [[SUInstallerConnection alloc] initWithDelegate:self];
    } else {
        self.installerConnection = [[SUXPCInstallerConnection alloc] initWithDelegate:self];
    }
    
    __weak SUInstallerDriver *weakSelf = self;
    [self.installerConnection setInvalidationHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            SUInstallerDriver *strongSelf = weakSelf;
            if (strongSelf.installerConnection != nil) {
                NSError *remoteError =
                [NSError
                 errorWithDomain:SUSparkleErrorDomain
                 code:SUInstallationError
                 userInfo:@{
                            NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while running the updater. Please try again later.", nil),
                            NSLocalizedFailureReasonErrorKey:@"The remote port connection was invalidated from the updater"
                            }
                 ];
                [strongSelf.delegate installerIsRequestingAbortInstallWithError:remoteError];
            }
        });
    }];
    
    NSString *serviceName = SUAutoUpdateServiceNameForBundleIdentifier(hostBundleIdentifier);
    
    [self.installerConnection setServiceName:serviceName];
    
    [self sendInstallationData];
}

// This can be called multiple times (eg: if a delta update fails, this may be called again with a regular update item)
- (void)extractDownloadName:(NSString *)downloadName withUpdateItem:(SUAppcastItem *)updateItem temporaryDirectory:(NSString *)temporaryDirectory completion:(void (^)(NSError * _Nullable))completionHandler
{
    self.updateItem = updateItem;
    self.temporaryDirectory = temporaryDirectory;
    self.downloadName = downloadName;
    
    self.currentStage = SUInstallerNotStarted;
    
    if (self.installerConnection == nil) {
        [self launchAutoUpdateWithCompletion:completionHandler];
    } else {
        // The Install tool is already alive; just send out installation input data again
        [self sendInstallationData];
        completionHandler(nil);
    }
}

- (void)resumeUpdateWithUpdateItem:(SUAppcastItem *)updateItem
{
    self.updateItem = updateItem;
}

- (void)sendInstallationData
{
    NSString *pathToRelaunch = [self.host bundlePath];
    if ([self.updaterDelegate respondsToSelector:@selector(pathToRelaunchForUpdater:)]) {
        pathToRelaunch = [self.updaterDelegate pathToRelaunchForUpdater:self.updater];
    }
    
    NSString *dsaSignature = (self.updateItem.DSASignature == nil) ? @"" : self.updateItem.DSASignature;
    
    NSString *decryptionPassword = nil;
    if ([self.updaterDelegate respondsToSelector:@selector(decryptionPasswordForUpdater:)]) {
        decryptionPassword = [self.updaterDelegate decryptionPasswordForUpdater:self.updater];
    }
    
    NSString *localProgressToolPath = [self.sparkleBundle pathForResource:@""SPARKLE_INSTALLER_PROGRESS_TOOL_NAME ofType:@"app"];
    if (localProgressToolPath == nil) {
        SULog(@"Error: Failed to find installer progress tool: %@", localProgressToolPath);
    }
    
    NSError *progressToolError = nil;
    NSString *progressToolPath = [self copyPathToCacheDirectory:localProgressToolPath error:&progressToolError];
    if (progressToolPath == nil) {
        SULog(@"Error: Failed to copy or find installer progress tool: %@", progressToolError);
    }
    
    SUInstallationInputData *installationData = [[SUInstallationInputData alloc] initWithRelaunchPath:pathToRelaunch progressToolPath:progressToolPath hostBundlePath:self.host.bundlePath updateDirectoryPath:self.temporaryDirectory downloadName:self.downloadName dsaSignature:dsaSignature decryptionPassword:decryptionPassword];
    
    NSData *archivedData = SUArchiveRootObjectSecurely(installationData);
    if (archivedData == nil) {
        [self.delegate installerIsRequestingAbortInstallWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey:SULocalizedString(@"An error occurred while encoding the installer parameters. Please try again later.", nil) }]];
        return;
    }
    
    [self.installerConnection handleMessageWithIdentifier:SUInstallationData data:archivedData];
    
    self.currentStage = SUInstallerNotStarted;
    
    // If the number of extractions attempts stays the same, then we've waited too long and should abort the installation
    // The extraction attempts is incremented when we receive an extraction should start message from the installer
    // This also handles the case when a delta extraction fails and tries to re-try another extraction attempt later
    // We will also want to make sure current stage is still SUInstallerNotStarted because it may not be due to resumability
    NSUInteger currentExtractionAttempts = self.extractionAttempts;
    __weak SUInstallerDriver *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(FIRST_INSTALLER_MESSAGE_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        SUInstallerDriver *strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf.currentStage == SUInstallerNotStarted && currentExtractionAttempts == self.extractionAttempts) {
            SULog(@"Timeout: Installer never started archive extraction");
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
    if (!SUInstallerMessageTypeIsLegal(self.currentStage, identifier)) {
        SULog(@"Error: received out of order message with current stage: %d, requested stage: %d", self.currentStage, identifier);
        return;
    }
    
    if (identifier == SUExtractionStarted) {
        self.extractionAttempts++;
        self.currentStage = identifier;
    } else if (identifier == SUExtractedArchiveWithProgress) {
        if (data.length == sizeof(double) && sizeof(double) == sizeof(uint64_t)) {
            uint64_t progressValue = CFSwapInt64LittleToHost(*(const uint64_t *)data.bytes);
            double progress = *(double *)&progressValue;
            [self.delegate installerDidExtractUpdateWithProgress:progress];
            self.currentStage = identifier;
        }
    } else if (identifier == SUArchiveExtractionFailed) {
        // If this is a delta update, there must be a regular update we can fall back to
        if ([self.updateItem isDeltaUpdate]) {
            [self.delegate installerDidFailToApplyDeltaUpdate];
        } else {
            // Don't have to store current stage because we're going to abort
            [self.delegate installerIsRequestingAbortInstallWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey:SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil) }]];
        }
    } else if (identifier == SUValidationStarted) {
        self.currentStage = identifier;
    } else if (identifier == SUInstallationStartedStage1) {
        self.currentStage = identifier;
        [self.delegate installerDidStartInstalling];
        self.startedInstalling = YES;
        
    } else if (identifier == SUInstallationFinishedStage1) {
        self.currentStage = identifier;
        
        // Let the installer keep a copy of the appcast item data
        // We may want to ask for it later (note the updater can relaunch without the app necessarily having relaunched)
        NSData *updateItemData = SUArchiveRootObjectSecurely(self.updateItem);
        
        if (updateItemData != nil) {
            [self.installerConnection handleMessageWithIdentifier:SUSentUpdateAppcastItemData data:updateItemData];
        } else {
            SULog(@"Error: Archived data to send for appcast item is nil");
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
    } else if (identifier == SUInstallationFinishedStage2) {
        self.currentStage = identifier;
        
        BOOL cancelledInstallation = NO;
        if (data.length >= sizeof(uint8_t)) {
            cancelledInstallation = (*(const uint8_t *)data.bytes == 0x1);
        }
        
        if (cancelledInstallation) {
            [self.delegate installerIsRequestingAbortInstallWithError:nil];
        } else {
            if (!self.startedInstalling) {
                // It's possible we can start from resuming to stage 2 rather than doing stage 1 again, so we should notify to start installing if we haven't done so already
                self.startedInstalling = YES;
                [self.delegate installerDidStartInstalling];
            }
            
            BOOL hasTargetTerminated = NO;
            if (data.length >= sizeof(uint8_t) * 2) {
                hasTargetTerminated = (BOOL)*((const uint8_t *)data.bytes + 1);
            }
            
            [self.delegate installerWillFinishInstallationAndRelaunch:self.willRelaunch];
            
            if (!hasTargetTerminated) {
                [self.delegate installerIsRequestingAppTermination];
            }
        }
    } else if (identifier == SUInstallationFinishedStage3) {
        self.currentStage = identifier;
        
        [self.installerConnection invalidate];
        self.installerConnection = nil;
        
        [self.delegate installerDidFinishInstallation];
        [self.delegate installerIsRequestingAbortInstallWithError:nil];
    } else if (identifier == SUUpdaterAlivePing) {
        // Don't update the current stage; a ping request has no effect on that.
        [self.installerConnection handleMessageWithIdentifier:SUUpdaterAlivePong data:[NSData data]];
    }
}

// Creates intermediate directories up until targetPath if they don't already exist,
// and removes the directory at targetPath if one already exists there
- (BOOL)preparePath:(NSString *)targetPath error:(NSError * __autoreleasing *)error
{
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    if ([fileManager fileExistsAtPath:targetPath]) {
        NSError *removeError = nil;
        if (![fileManager removeItemAtPath:targetPath error:&removeError]) {
            if (error != NULL) {
                *error = removeError;
            }
            return NO;
        }
    } else {
        NSError *createDirectoryError = nil;
        if (![fileManager createDirectoryAtPath:[targetPath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:@{} error:&createDirectoryError]) {
            if (error != NULL) {
                *error = createDirectoryError;
            }
            return NO;
        }
    }
    return YES;
}

- (NSString *)copyPathToCacheDirectory:(NSString *)pathToCopy error:(NSError * __autoreleasing *)error
{
    // Copy the resource into the caches directory so we can get to it after the new version's installed.
    // Only the paranoid survive: if there's already a stray copy of resource there, we would have problems.
    NSString *cachePath = nil;
    if (pathToCopy == nil) {
        if (error != NULL) {
            *error =
            [NSError
             errorWithDomain:SUSparkleErrorDomain
             code:SURelaunchError
             userInfo:@{
                        NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"An error occurred while relaunching %1$@, but the new version will be available next time you run %1$@.", nil), [self.host name]],
                        NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't find the relauncher (expected to find it at %@)", pathToCopy]
                        }
             ];
        }
    } else {
        NSString *targetPath = [self.cachePath stringByAppendingPathComponent:[pathToCopy lastPathComponent]];
        
        SUFileManager *fileManager = [SUFileManager defaultManager];
        
        NSURL *urlToCopy = [NSURL fileURLWithPath:pathToCopy];
        NSURL *targetURL = [NSURL fileURLWithPath:targetPath];
        
        NSError *prepareOrCopyError = nil;
        
        // We only need to run our copy of the app by spawning a task
        // Since we are copying the app to a directory that is write-accessible, we don't need to muck with owner/group IDs
        if ([self preparePath:targetPath error:&prepareOrCopyError] && [fileManager copyItemAtURL:urlToCopy toURL:targetURL error:&prepareOrCopyError]) {
            cachePath = targetPath;
        } else {
            if (error != NULL) {
                *error =
                [NSError
                 errorWithDomain:SUSparkleErrorDomain
                 code:SURelaunchError
                 userInfo:@{
                            NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil),
                            NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't copy relauncher (%@) to temporary path (%@)! %@", pathToCopy, targetPath, (prepareOrCopyError ? [prepareOrCopyError localizedDescription] : @"")]
                            }
                 ];
            }
        }
    }
    
    return cachePath;
}

- (void)launchAutoUpdateWithCompletion:(void (^)(NSError *_Nullable))completionHandler
{
    // Copy the relauncher into a temporary directory so we can get to it after the new version's installed.
    // Only the paranoid survive: if there's already a stray copy of relaunch there, we would have problems.
    NSError *relaunchError = nil;
    NSString *relaunchToolPath = [self copyPathToCacheDirectory:[self.sparkleBundle pathForResource:@""SPARKLE_RELAUNCH_TOOL_NAME ofType:@"app"] error:&relaunchError];
    if (relaunchToolPath == nil) {
        completionHandler(relaunchError);
        return;
    }
    
    NSString *hostBundleIdentifier = self.host.bundle.bundleIdentifier;
    if (hostBundleIdentifier == nil) {
        NSError *error =
        [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey:SULocalizedString(@"An error occurred while finding the application's bundle identifier. Please try again later.", nil) }];
        
        completionHandler(error);
        return;
    }
    
    id<SUInstallerLauncherProtocol> installerLauncher = nil;
    __block BOOL retrievedLaunchStatus = NO;
    NSXPCConnection *launcherConnection = nil;
    
    if (!SUXPCServiceExists(@INSTALLER_LAUNCHER_PRODUCT_NAME)) {
        installerLauncher = [[SUInstallerLauncher alloc] init];
    } else {
        launcherConnection = [[NSXPCConnection alloc] initWithServiceName:@INSTALLER_LAUNCHER_BUNDLE_ID];
        launcherConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerLauncherProtocol)];
        [launcherConnection resume];
        
        __weak NSXPCConnection *weakConnection = launcherConnection;
        launcherConnection.interruptionHandler = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!retrievedLaunchStatus) {
                    [weakConnection invalidate];
                }
            });
        };
        
        launcherConnection.invalidationHandler = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!retrievedLaunchStatus) {
                    NSError *error =
                    [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey:SULocalizedString(@"An error occurred while connecting to the installer. Please try again later.", nil) }];
                    
                    completionHandler(error);
                }
            });
        };
        
        installerLauncher = launcherConnection.remoteObjectProxy;
    }
    
    BOOL shouldAllowInstallerInteraction = NO;
    if ([self.updaterDelegate respondsToSelector:@selector(updaterShouldAllowInstallerInteraction:)]) {
        shouldAllowInstallerInteraction = [self.updaterDelegate updaterShouldAllowInstallerInteraction:self.updater];
    }
    
    [installerLauncher launchInstallerAtPath:relaunchToolPath withHostBundleIdentifier:hostBundleIdentifier allowingInteraction:shouldAllowInstallerInteraction completion:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            retrievedLaunchStatus = YES;
            [launcherConnection invalidate];
            
            if (!success) {
                NSError *error =
                [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey:SULocalizedString(@"An error occurred while launching the installer. Please try again later.", nil) }];
                
                completionHandler(error);
            } else {
                [self setUpConnection];
                
                completionHandler(nil);
            }
        });
    }];
}

- (BOOL)mayUpdateAndRestart
{
    return (!self.updaterDelegate || ![self.updaterDelegate respondsToSelector:@selector(updaterShouldRelaunchApplication:)] || [self.updaterDelegate updaterShouldRelaunchApplication:self.updater]);
}

// Only implemented due to backwards compability reasons; see -installWithToolAndRelaunch:displayingUserInterface: below
- (void)installWithToolAndRelaunch:(BOOL)relaunch
{
    [self installWithToolAndRelaunch:relaunch displayingUserInterface:relaunch];
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
            __weak SUInstallerDriver *weakSelf = self;
            if ([self.updaterDelegate updater:self.updater shouldPostponeRelaunchForUpdate:self.updateItem untilInvokingBlock:^{
                [weakSelf installWithToolAndRelaunch:relaunch displayingUserInterface:showUI];
            }]) {
                return;
            }
        } else if ([self.updaterDelegate respondsToSelector:@selector(updater:shouldPostponeRelaunchForUpdate:untilInvoking:)]) {
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:@selector(installWithToolAndRelaunch:)]];
            [invocation setSelector:@selector(installWithToolAndRelaunch:)];
            [invocation setArgument:&relaunch atIndex:2];
            [invocation setTarget:self];
            self.postponedOnce = YES;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            if ([self.updaterDelegate updater:self.updater shouldPostponeRelaunchForUpdate:self.updateItem untilInvoking:invocation]) {
#pragma clang diagnostic pop
                return;
            }
        }
    }
    
    // Set up connection to the installer if one is not set up already
    [self setUpConnection];
    
    // For resumability, we'll assume we are far enough for the installation to continue
    self.currentStage = SUInstallationFinishedStage1;
    
    self.willRelaunch = relaunch;
    
    uint8_t response[2] = {(uint8_t)relaunch, (uint8_t)showUI};
    NSData *responseData = [NSData dataWithBytes:response length:sizeof(response)];
    
    [self.installerConnection handleMessageWithIdentifier:SUResumeInstallationToStage2 data:responseData];
    
    // we'll terminate later when the installer tells us stage 2 is done
}

- (void)abortInstall
{
    if (self.installerConnection != nil) {
        [self.installerConnection invalidate];
        self.installerConnection = nil;
    }
}

@end
