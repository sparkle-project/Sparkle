//
//  AppInstaller.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/7/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "AppInstaller.h"
#import "TerminationListener.h"
#import "SUInstaller.h"
#import "SUUpdateValidator.h"
#import "SULog.h"
#import "SULog+NSError.h"
#import "SUHost.h"
#import "SULocalizations.h"
#import "SUStandardVersionComparator.h"
#import "SPUMessageTypes.h"
#import "SPUSecureCoding.h"
#import "SPUInstallationInputData.h"
#import "SUUnarchiver.h"
#import "SUFileManager.h"
#import "SPUInstallationInfo.h"
#import "SUAppcastItem.h"
#import "SUErrors.h"
#import "SUInstallerCommunicationProtocol.h"
#import "AgentConnection.h"
#import "SPUInstallerAgentProtocol.h"
#import "SPUInstallationType.h"
#import "SPULocalCacheDirectory.h"


#include "AppKitPrevention.h"

#define FIRST_UPDATER_MESSAGE_TIMEOUT 7ull
#define RETRIEVE_PROCESS_IDENTIFIER_TIMEOUT 5ull

/**
 * Show display progress UI after a delay from starting the final part of the installation.
 * This should be long enough so that we don't show progress for very fast installations, but
 * short enough so that we don't leave the user wondering why nothing is happening.
 */
static const NSTimeInterval SUDisplayProgressTimeDelay = 0.7;

@interface AppInstaller () <NSXPCListenerDelegate, SUInstallerCommunicationProtocol, AgentConnectionDelegate>

@property (nonatomic) NSXPCListener* xpcListener;
@property (nonatomic) NSXPCConnection *activeConnection;
@property (nonatomic) id<SUInstallerCommunicationProtocol> communicator;
@property (nonatomic) AgentConnection *agentConnection;
@property (nonatomic) BOOL receivedUpdaterPong;

@property (nonatomic, strong) TerminationListener *terminationListener;

@property (nonatomic) SUUpdateValidator *updateValidator;

@property (nonatomic, readonly, copy) NSString *hostBundleIdentifier;
@property (nonatomic, readonly) NSString *homeDirectory;
@property (nonatomic, readonly) NSString *userName;
@property (nonatomic) SUHost *host;
@property (nonatomic, copy) NSString *updateDirectoryPath;
@property (nonatomic, copy) NSString *downloadName;
@property (nonatomic, copy) NSString *decryptionPassword;
@property (nonatomic, strong) SUSignatures *signatures;
@property (nonatomic, copy) NSString *relaunchPath;
@property (nonatomic, copy) NSString *installationType;
@property (nonatomic, assign) BOOL shouldRelaunch;
@property (nonatomic, assign) BOOL shouldShowUI;

@property (nonatomic) id<SUInstallerProtocol> installer;
@property (nonatomic) BOOL willCompleteInstallation;
@property (nonatomic) BOOL receivedInstallationData;
@property (nonatomic) BOOL finishedValidation;
@property (nonatomic) BOOL agentInitiatedConnection;

@property (nonatomic) dispatch_queue_t installerQueue;
@property (nonatomic) BOOL performedStage1Installation;
@property (nonatomic) BOOL performedStage2Installation;
@property (nonatomic) BOOL performedStage3Installation;

@end

@implementation AppInstaller

@synthesize xpcListener = _xpcListener;
@synthesize activeConnection = _activeConnection;
@synthesize communicator = _communicator;
@synthesize agentConnection = _agentConnection;
@synthesize receivedUpdaterPong = _receivedUpdaterPong;
@synthesize hostBundleIdentifier = _hostBundleIdentifier;
@synthesize homeDirectory = _homeDirectory;
@synthesize userName = _userName;
@synthesize terminationListener = _terminationListener;
@synthesize updateValidator = _updateValidator;
@synthesize host = _host;
@synthesize updateDirectoryPath = _updateDirectoryPath;
@synthesize downloadName = _downloadName;
@synthesize decryptionPassword = _decryptionPassword;
@synthesize signatures = _signatures;
@synthesize relaunchPath = _relaunchPath;
@synthesize installationType = _installationType;
@synthesize shouldRelaunch = _shouldRelaunch;
@synthesize shouldShowUI = _shouldShowUI;
@synthesize installer = _installer;
@synthesize willCompleteInstallation = _willCompleteInstallation;
@synthesize receivedInstallationData = _receivedInstallationData;
@synthesize installerQueue = _installerQueue;
@synthesize performedStage1Installation = _performedStage1Installation;
@synthesize performedStage2Installation = _performedStage2Installation;
@synthesize performedStage3Installation = _performedStage3Installation;
@synthesize finishedValidation = _finishedValidation;
@synthesize agentInitiatedConnection = _agentInitiatedConnection;

- (instancetype)initWithHostBundleIdentifier:(NSString *)hostBundleIdentifier homeDirectory:(NSString *)homeDirectory userName:(NSString *)userName
{
    if (!(self = [super init])) {
        return nil;
    }
    
    _hostBundleIdentifier = [hostBundleIdentifier copy];
    
    _homeDirectory = [homeDirectory copy];
    _userName = [userName copy];
    
    _xpcListener = [[NSXPCListener alloc] initWithMachServiceName:SPUInstallerServiceNameForBundleIdentifier(hostBundleIdentifier)];
    _xpcListener.delegate = self;
    
    _agentConnection = [[AgentConnection alloc] initWithHostBundleIdentifier:hostBundleIdentifier delegate:self];
    
    return self;
}

- (BOOL)listener:(NSXPCListener *)__unused listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection
{
    if (self.activeConnection != nil) {
        SULog(SULogLevelDefault, @"Rejecting multiple connections...");
        [newConnection invalidate];
        return NO;
    }
    
    self.activeConnection = newConnection;
    
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerCommunicationProtocol)];
    newConnection.exportedObject = self;
    
    newConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerCommunicationProtocol)];
    
    __weak AppInstaller *weakSelf = self;
    newConnection.interruptionHandler = ^{
        [weakSelf.activeConnection invalidate];
    };
    
    newConnection.invalidationHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            AppInstaller *strongSelf = weakSelf;
            if (strongSelf != nil) {
                if (strongSelf.activeConnection != nil && !strongSelf.willCompleteInstallation) {
                    [strongSelf cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Invalidation on remote port being called, and installation is not close enough to completion!" }]];
                }
                strongSelf.communicator = nil;
                strongSelf.activeConnection = nil;
            }
        });
    };
    
    [newConnection resume];
    
    self.communicator = newConnection.remoteObjectProxy;
    
    return YES;
}

- (void)start
{
    [self.xpcListener resume];
    [self.agentConnection startListener];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(FIRST_UPDATER_MESSAGE_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.receivedInstallationData) {
            [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Timeout: installation data was never received" }]];
        }
        
        if (!self.agentConnection.connected) {
            [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Timeout: agent connection was never initiated" }]];
        }
    });
}

- (void)extractAndInstallUpdate
{
    [self.communicator handleMessageWithIdentifier:SPUExtractionStarted data:[NSData data]];
    
    NSString *archivePath = [self.updateDirectoryPath stringByAppendingPathComponent:self.downloadName];
    id<SUUnarchiverProtocol> unarchiver = [SUUnarchiver unarchiverForPath:archivePath updatingHostBundlePath:self.host.bundlePath decryptionPassword:self.decryptionPassword expectingInstallationType:self.installationType];
    
    NSError *unarchiverError = nil;
    BOOL success = NO;
    if (!unarchiver) {
        unarchiverError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No valid unarchiver was found for %@", archivePath] }];
        
        success = NO;
    } else {
        self.updateValidator = [[SUUpdateValidator alloc] initWithDownloadPath:archivePath signatures:self.signatures host:self.host];

        // Delta & package updates will require validation before extraction
        // Normal application updates are a bit more lenient allowing developers to change one of apple dev ID or DSA keys
        BOOL needsPrevalidation = [[unarchiver class] mustValidateBeforeExtraction] || ![self.installationType isEqualToString:SPUInstallationTypeApplication];

        if (needsPrevalidation) {
            success = [self.updateValidator validateDownloadPathWithError:&unarchiverError];
        } else {
            success = YES;
        }
    }
    
    if (!success) {
        [self unarchiverDidFailWithError:unarchiverError];
    } else {
        [unarchiver
         unarchiveWithCompletionBlock:^(NSError * _Nullable error) {
             if (error != nil) {
                 [self unarchiverDidFailWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to unarchive %@", archivePath], NSUnderlyingErrorKey: (NSError * _Nonnull)error }]];
             } else {
                 [self.communicator handleMessageWithIdentifier:SPUValidationStarted data:[NSData data]];
                 
                 NSError *validationError = nil;
                 BOOL validationSuccess = [self.updateValidator validateWithUpdateDirectory:self.updateDirectoryPath error:&validationError];
                 
                 if (!validationSuccess) {
                     [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Update validation was a failure", NSUnderlyingErrorKey: validationError }]];
                 } else {
                     [self.communicator handleMessageWithIdentifier:SPUInstallationStartedStage1 data:[NSData data]];
                     
                     self.finishedValidation = YES;
                     if (self.agentInitiatedConnection) {
                         [self retrieveProcessIdentifierAndStartInstallation];
                     }
                 }
             }
         }
         progressBlock:^(double progress) {
             if (sizeof(progress) == sizeof(uint64_t)) {
                 uint64_t progressValue = CFSwapInt64HostToLittle(*(uint64_t *)&progress);
                 NSData *data = [NSData dataWithBytes:&progressValue length:sizeof(progressValue)];
                 
                 [self.communicator handleMessageWithIdentifier:SPUExtractedArchiveWithProgress data:data];
             }
         }];
    }
}

- (void)clearUpdateDirectory
{
    if (self.updateDirectoryPath != nil) {
        NSError *theError = nil;
        if (![[[SUFileManager alloc] init] removeItemAtURL:[NSURL fileURLWithPath:self.updateDirectoryPath] error:&theError]) {
            SULog(SULogLevelError, @"Couldn't remove update folder: %@.", theError);
        }
        self.updateDirectoryPath = nil;
    }
}

- (void)unarchiverDidFailWithError:(NSError *)error
{
    SULog(SULogLevelError, @"Failed to unarchive file");
    SULogError(error);
    
    // No longer need update validator until next possible extraction (eg: if initial delta update fails)
    self.updateValidator = nil;
    
    // Client could try update again with different inputs
    // Eg: one common case is if a delta update fails, client may want to fall back to regular update
    // We really only need to set updateDirectoryPath to nil since that's the field we check if we've received installation data,
    // but may as well set other fields to nil too
    [self clearUpdateDirectory];
    self.downloadName = nil;
    self.decryptionPassword = nil;
    self.signatures = nil;
    self.relaunchPath = nil;
    self.host = nil;
    
    NSData *archivedError = SPUArchiveRootObjectSecurely(error);
    [self.communicator handleMessageWithIdentifier:SPUArchiveExtractionFailed data:archivedError != nil ? archivedError : [NSData data]];
}

- (void)agentConnectionDidInitiate
{
    self.agentInitiatedConnection = YES;
    if (self.finishedValidation) {
        [self retrieveProcessIdentifierAndStartInstallation];
    }
}

- (void)agentConnectionDidInvalidate
{
    if (!self.finishedValidation || !self.agentInitiatedConnection) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{ NSLocalizedDescriptionKey: @"Error: Agent connection invalidated before installation began" }];
        
        NSError *agentError = self.agentConnection.invalidationError;
        if (agentError != nil) {
            userInfo[NSUnderlyingErrorKey] = agentError;
        }
        
        [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:userInfo]];
    }
}

- (void)retrieveProcessIdentifierAndStartInstallation
{
    // We use the relaunch path for the bundle to listen for termination instead of the host path
    // For a plug-in this makes a big difference; we want to wait until the app hosting the plug-in terminates
    // Otherwise for an app, the relaunch path and host path should be identical
    
    [self.agentConnection.agent registerApplicationBundlePath:self.relaunchPath reply:^(NSNumber * _Nullable processIdentifier) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.terminationListener = [[TerminationListener alloc] initWithProcessIdentifier:processIdentifier];
            [self startInstallation];
        });
    }];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(RETRIEVE_PROCESS_IDENTIFIER_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self.terminationListener == nil) {
            [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Timeout error: failed to retreive process identifier from agent" }]];
        }
    });
}

- (void)handleMessageWithIdentifier:(int32_t)identifier data:(NSData *)data
{
    if (identifier == SPUInstallationData && self.updateDirectoryPath == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Mark that we have received the installation data
            // Do not rely on eg: self.ipdateDirectoryPath != nil because we may set it to nil again if an early stage fails (i.e, archive extraction)
            self.receivedInstallationData = YES;
            
            SPUInstallationInputData *installationData = (SPUInstallationInputData *)SPUUnarchiveRootObjectSecurely(data, [SPUInstallationInputData class]);
            if (installationData == nil) {
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Error: Failed to unarchive input installation data" }]];
                return;
            }
            
            NSString *installationType = installationData.installationType;
            if (!SPUValidInstallationType(installationType)) {
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Error: Received invalid installation type: %@", installationType] }]];
                return;
            }
            
            NSBundle *hostBundle = [NSBundle bundleWithPath:installationData.hostBundlePath];
            
            NSString *bundleIdentifier = hostBundle.bundleIdentifier;
            if (bundleIdentifier == nil || ![bundleIdentifier isEqualToString:self.hostBundleIdentifier]) {
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Error: Failed to match host bundle identifiers %@ and %@", self.hostBundleIdentifier, bundleIdentifier] }]];
                return;
            }
            
            // This will be important later
            if (installationData.relaunchPath == nil) {
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Error: Failed to obtain relaunch path from installation data" }]];
                return;
            }
            
            // This installation path is specific to sparkle and the bundle identifier
            NSString *rootCacheInstallationPath = [[SPULocalCacheDirectory cachePathForBundleIdentifier:bundleIdentifier] stringByAppendingPathComponent:@"Installation"];
            
            [SPULocalCacheDirectory removeOldItemsInDirectory:rootCacheInstallationPath];
            
            NSString *cacheInstallationPath = [SPULocalCacheDirectory createUniqueDirectoryInDirectory:rootCacheInstallationPath];
            if (cacheInstallationPath == nil) {
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Error: Failed to create installation cache directory in %@", rootCacheInstallationPath] }]];
                return;
            }
            
            // Move the download archive to somewhere where probably only we will be touching it
            // This prevents eg: if a bug exists in the updater that removes files we are trying to install
            // When this tool is ran as root, we are moving it into a directory that only root will have access to
            NSURL *downloadURL = [[NSURL fileURLWithPath:installationData.updateDirectoryPath] URLByAppendingPathComponent:installationData.downloadName];
            
            NSURL *downloadDestinationURL = [[NSURL fileURLWithPath:cacheInstallationPath] URLByAppendingPathComponent:installationData.downloadName];
            
            NSError *moveError = nil;
            if (![[[SUFileManager alloc] init] moveItemAtURL:downloadURL toURL:downloadDestinationURL error:&moveError]) {
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Error: Failed to move download archive to new location", NSUnderlyingErrorKey: moveError }]];
                return;
            }
            
            // Make sure the downloaded archive we moved over is a regular file and not a symbolic link placed by an attacker
            NSError *attributesError = nil;
            NSString *downloadDestinationPath = downloadDestinationURL.path;
            if (downloadDestinationPath == nil) {
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Error: Failed to retrieve download archive path from %@", downloadDestinationURL] }]];
                
                return;
            }
            
            NSDictionary<NSString *, id> *archiveAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:downloadDestinationPath error:&attributesError];
            
            if (archiveAttributes == nil) {
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Error: Failed to retrieve download archive attributes from %@", downloadDestinationPath] }]];
                
                return;
            }
            
            if (![(NSString *)archiveAttributes[NSFileType] isEqualToString:NSFileTypeRegular]) {
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Error: Received bad archive file type: %@", archiveAttributes[NSFileType]] }]];
                return;
            }
            
            // Carry these properities separately rather than using the SUInstallationInputData object
            // Some of our properties may slightly differ than our input and we don't want to make the mistake of using one of those
            self.installationType = installationType;
            self.relaunchPath = installationData.relaunchPath;
            self.downloadName = installationData.downloadName;
            self.signatures = installationData.signatures;
            self.updateDirectoryPath = cacheInstallationPath;
            self.host = [[SUHost alloc] initWithBundle:hostBundle];
            
            [self extractAndInstallUpdate];
        });
    } else if (identifier == SPUSentUpdateAppcastItemData) {
        SUAppcastItem *updateItem = (SUAppcastItem *)SPUUnarchiveRootObjectSecurely(data, [SUAppcastItem class]);
        if (updateItem != nil) {
            SPUInstallationInfo *installationInfo = [[SPUInstallationInfo alloc] initWithAppcastItem:updateItem canSilentlyInstall:[self.installer canInstallSilently]];
            
            NSData *archivedData = SPUArchiveRootObjectSecurely(installationInfo);
            if (archivedData != nil) {
                [self.agentConnection.agent registerInstallationInfoData:archivedData];
            }
        }
    } else if (identifier == SPUResumeInstallationToStage2 && data.length == sizeof(uint8_t) * 2) {
        // Because anyone can ask us to resume the installation, it may be wise to think about backwards compatibility here if IPC changes
        uint8_t relaunch = *((const uint8_t *)data.bytes);
        uint8_t showsUI = *((const uint8_t *)data.bytes + 1);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // This flag has an impact on interactive type installations and showing UI progress during non-interactive installations
            self.shouldShowUI = (BOOL)showsUI;
            // Don't test if the application was alive initially, leave that to the progress agent if we decide to relaunch
            self.shouldRelaunch = (BOOL)relaunch;
            
            if (self.performedStage1Installation) {
                // Resume the installation if we aren't done with stage 2 yet, and remind the client we are prepared to relaunch
                dispatch_async(self.installerQueue, ^{
                    [self performStage2InstallationIfNeeded];
                });
            }
        });
    } else if (identifier == SPUCancelInstallation) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self cleanupAndExitWithStatus:0 error:nil];
        });
    } else if (identifier == SPUUpdaterAlivePong) {
        self.receivedUpdaterPong = YES;
    }
}

- (void)startInstallation
{
    self.willCompleteInstallation = YES;
    
    self.installerQueue = dispatch_queue_create("org.sparkle-project.sparkle.installer", DISPATCH_QUEUE_SERIAL);
    
    dispatch_async(self.installerQueue, ^{
        NSError *installerError = nil;
        id <SUInstallerProtocol> installer = [SUInstaller installerForHost:self.host expectedInstallationType:self.installationType updateDirectory:self.updateDirectoryPath homeDirectory:self.homeDirectory userName:self.userName error:&installerError];
        
        if (installer == nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Error: Failed to create installer instance", NSUnderlyingErrorKey: installerError }]];
            });
            return;
        }
        
        NSError *firstStageError = nil;
        if (![installer performInitialInstallation:&firstStageError]) {
            self.installer = nil;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Error: Failed to start installer", NSUnderlyingErrorKey: firstStageError }]];
            });
            return;
        }
        
        uint8_t canPerformSilentInstall = (uint8_t)[installer canInstallSilently];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.installer = installer;
            
            uint8_t targetTerminated = (uint8_t)self.terminationListener.terminated;
            
            uint8_t sendInformation[] = {canPerformSilentInstall, targetTerminated};
            
            NSData *sendData = [NSData dataWithBytes:sendInformation length:sizeof(sendInformation)];
            
            [self.communicator handleMessageWithIdentifier:SPUInstallationFinishedStage1 data:sendData];
            
            self.performedStage1Installation = YES;
            
            // Stage 2 can still be run before we finish installation
            // if the updater requests for it before the app is terminated
            [self finishInstallationAfterHostTermination];
        });
    });
}

- (void)performStage2InstallationIfNeeded
{
    if (self.performedStage2Installation) {
        return;
    }
    
    BOOL performedSecondStage = self.shouldShowUI || [self.installer canInstallSilently];
    if (performedSecondStage) {
        self.performedStage2Installation = YES;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            uint8_t targetTerminated = (uint8_t)self.terminationListener.terminated;
            
            NSData *sendData = [NSData dataWithBytes:&targetTerminated length:sizeof(targetTerminated)];
            [self.communicator handleMessageWithIdentifier:SPUInstallationFinishedStage2 data:sendData];
            
            // Don't check if the target is already terminated, leave that to the progress agent
            // We could be slightly off if there were multiple instances running
            [self.agentConnection.agent sendTerminationSignal];
        });
    } else {
        self.installer = nil;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Error: Failed to resume installer on stage 2 because installation cannot be installed silently" }]];
        });
    }
}

- (void)finishInstallationAfterHostTermination
{
    [self.terminationListener startListeningWithCompletion:^(BOOL success) {
        if (!success) {
            [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Failed to listen for application termination" }]];
            return;
        }
        
        // Show our installer progress UI tool if only after a certain amount of time passes,
        // and if our installer is silent (i.e, doesn't show progress on its own)
        __block BOOL shouldShowUIProgress = YES;
        if (self.shouldShowUI && [self.installer canInstallSilently]) {
            // Ask the updater if it is still alive
            // If they are, we will receive a pong response back
            // Reset if we received a pong just to be on the safe side
            self.receivedUpdaterPong = NO;
            [self.communicator handleMessageWithIdentifier:SPUUpdaterAlivePing data:[NSData data]];
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SUDisplayProgressTimeDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                // Make sure we're still eligible for showing the installer progress
                // Also if the updater process is still alive, showing the progress should not be our duty
                // if the communicator object is nil, the updater definitely isn't alive. However, if it is not nil,
                // this does not necessarily mean the updater is alive, so we should also check if we got a recent response back from the updater
                if (shouldShowUIProgress && (!self.receivedUpdaterPong || self.communicator == nil)) {
                    [self.agentConnection.agent showProgress];
                }
            });
        }
        
        dispatch_async(self.installerQueue, ^{
            [self performStage2InstallationIfNeeded];
            
            if (!self.performedStage2Installation) {
                // We failed and we're going to exit shortly
                return;
            }
            
            NSError *thirdStageError = nil;
            if (![self.installer performFinalInstallationProgressBlock:nil error:&thirdStageError]) {
                [self.installer performCleanup];
                self.installer = nil;
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Failed to finalize installation", NSUnderlyingErrorKey: thirdStageError }]];
                });
                return;
            }
            
            self.performedStage3Installation = YES;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                // Make sure to stop our displayed progress before we move onto cleanup & relaunch
                // This will also stop the agent from broadcasting the status info service, which we want to do before
                // we relaunch the app because the relaunched app could check the service upon launch..
                [self.agentConnection.agent stopProgress];
                shouldShowUIProgress = NO;
                
                [self.communicator handleMessageWithIdentifier:SPUInstallationFinishedStage3 data:[NSData data]];
                
                if (self.shouldRelaunch) {
                    // This will also signal to the agent that it will terminate soon
                    [self.agentConnection.agent relaunchApplication];
                }
                
                [self.installer performCleanup];
                
                [self cleanupAndExitWithStatus:EXIT_SUCCESS error:nil];
            });
        });
    }];
}

- (void)cleanupAndExitWithStatus:(int)status error:(NSError * _Nullable)error __attribute__((noreturn))
{
    if (error != nil) {
        SULogError(error);
        
        NSData *errorData = SPUArchiveRootObjectSecurely((NSError * _Nonnull)error);
        if (errorData != nil) {
            [self.communicator handleMessageWithIdentifier:SPUInstallerError data:errorData];
        }
    }
    
    // It's nice to tell the other end we're invalidating
    
    [self.activeConnection invalidate];
    self.activeConnection = nil;
    
    [self.xpcListener invalidate];
    self.xpcListener = nil;
    
    [self.agentConnection invalidate];
    self.agentConnection = nil;
    
    [self clearUpdateDirectory];
    
    exit(status);
}

@end
