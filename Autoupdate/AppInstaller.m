//
//  AppInstaller.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/7/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "AppInstaller.h"
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
#import "SPUVerifierInformation.h"
#import "SUConstants.h"


#include "AppKitPrevention.h"

#define FIRST_UPDATER_MESSAGE_TIMEOUT 18ull
#define RETRIEVE_PROCESS_IDENTIFIER_TIMEOUT 8ull

/**
 * Show display progress UI after a delay from starting the final part of the installation.
 * This should be long enough so that we don't show progress for very fast installations, but
 * short enough so that we don't leave the user wondering why nothing is happening.
 */
static const NSTimeInterval SUDisplayProgressTimeDelay = 0.7;

@interface AppInstaller () <NSXPCListenerDelegate, SUInstallerCommunicationProtocol, AgentConnectionDelegate>
@end

@implementation AppInstaller
{
    NSXPCListener* _xpcListener;
    NSXPCConnection *_activeConnection;
    id<SUInstallerCommunicationProtocol> _communicator;
    AgentConnection *_agentConnection;

    SUUpdateValidator *_updateValidator;

    NSString *_hostBundleIdentifier;
    NSString *_homeDirectory;
    NSString *_userName;
    SUHost *_host;
    NSString *_updateDirectoryPath;
    NSString *_extractionDirectory;
    NSString *_downloadName;
    NSString *_decryptionPassword;
    SUSignatures *_signatures;
    NSString *_relaunchPath;
    NSString *_installationType;
    SPUVerifierInformation *_verifierInformation;

    id<SUInstallerProtocol> _installer;

    dispatch_queue_t _installerQueue;
    
    BOOL _shouldRelaunch;
    BOOL _shouldShowUI;
    
    BOOL _receivedUpdaterPong;
    
    BOOL _willCompleteInstallation;
    BOOL _receivedInstallationData;
    BOOL _finishedValidation;
    BOOL _agentInitiatedConnection;
    
    BOOL _performedStage1Installation;
    BOOL _performedStage2Installation;
    BOOL _performedStage3Installation;
    
    BOOL _targetTerminated;
}

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
    if (_activeConnection != nil) {
        SULog(SULogLevelDefault, @"Rejecting multiple connections...");
        [newConnection invalidate];
        return NO;
    }
    
    _activeConnection = newConnection;
    
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerCommunicationProtocol)];
    newConnection.exportedObject = self;
    
    newConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerCommunicationProtocol)];
    
    __weak __typeof__(self) weakSelf = self;
    newConnection.interruptionHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __typeof__(self) strongSelf = weakSelf;
            if (strongSelf != nil) {
                [strongSelf->_activeConnection invalidate];
            }
        });
    };
    
    newConnection.invalidationHandler = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __typeof__(self) strongSelf = weakSelf;
            if (strongSelf != nil) {
                if (strongSelf->_activeConnection != nil && !strongSelf->_willCompleteInstallation) {
                    [strongSelf cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Invalidation on remote port being called, and installation is not close enough to completion!" }]];
                }
                strongSelf->_communicator = nil;
                strongSelf->_activeConnection = nil;
            }
        });
    };
    
    [newConnection resume];
    
    _communicator = newConnection.remoteObjectProxy;
    
    return YES;
}

- (void)start
{
    [_xpcListener resume];
    [_agentConnection startListener];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(FIRST_UPDATER_MESSAGE_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self->_receivedInstallationData) {
            [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Timeout: installation data was never received" }]];
        }
        
        if (!self->_agentConnection.connected) {
            [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Timeout: agent connection was never initiated" }]];
        }
    });
}

- (void)extractAndInstallUpdate SPU_OBJC_DIRECT
{
    [_communicator handleMessageWithIdentifier:SPUExtractionStarted data:[NSData data]];
    
    NSString *archivePath = [_updateDirectoryPath stringByAppendingPathComponent:_downloadName];
    
    id<SUUnarchiverProtocol> unarchiver = [SUUnarchiver unarchiverForPath:archivePath extractionDirectory:_extractionDirectory updatingHostBundlePath:_host.bundlePath decryptionPassword:_decryptionPassword expectingInstallationType:_installationType];
    
    NSError *prevalidationError = nil;
    BOOL success = NO;
    if (!unarchiver) {
        prevalidationError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"No valid unarchiver was found for %@", archivePath] }];
        
        success = NO;
    } else {
        NSError *fileAttributesError = nil;
        NSDictionary<NSFileAttributeKey, id> *archiveFileAttributes = [NSFileManager.defaultManager attributesOfItemAtPath:archivePath error:&fileAttributesError];
        if (archiveFileAttributes == nil) {
            SULog(SULogLevelError, @"Failed to retrieve file attributes from archive: %@.", fileAttributesError);
        } else {
            _verifierInformation.actualContentLength = (uint64_t)(archiveFileAttributes.fileSize);
        }
        
        _updateValidator = [[SUUpdateValidator alloc] initWithDownloadPath:archivePath signatures:_signatures host:_host verifierInformation:_verifierInformation];
        
        // More uncommon archives types (.aar, .yaa) need SUVerifyUpdateBeforeExtraction
        BOOL verifyBeforeExtraction = [_host boolForInfoDictionaryKey:SUVerifyUpdateBeforeExtractionKey];
        if (!verifyBeforeExtraction && unarchiver.needsVerifyBeforeExtractionKey) {
            prevalidationError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUValidationError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Extracting %@ archives require setting %@ to YES in the old app. Please visit https://sparkle-project.org/documentation/customization/ for more information.", archivePath.pathExtension, SUVerifyUpdateBeforeExtractionKey] }];
            
            success = NO;
        } else {
            // Delta, package updates, and apps with SUVerifyUpdateBeforeExtraction will require validation before extraction
            // Otherwise normal application updates are a bit more lenient allowing developers to change one of apple dev ID or EdDSA keys after extraction
            BOOL archiveTypeMustValidateBeforeExtraction = [[unarchiver class] mustValidateBeforeExtraction];
            BOOL needsPrevalidation = verifyBeforeExtraction || archiveTypeMustValidateBeforeExtraction || ![_installationType isEqualToString:SPUInstallationTypeApplication];

            if (needsPrevalidation) {
                // EdDSA signing is required, so host must have public keys
                if (![_updateValidator validateHostHasPublicKeys:&prevalidationError]) {
                    success = NO;
                } else {
                    // Falling back on code signing for prevalidation requires SUVerifyUpdateBeforeExtraction
                    // and that update is a regular app update, and not a delta update
                    BOOL fallbackOnCodeSigning = (verifyBeforeExtraction && !archiveTypeMustValidateBeforeExtraction && [_installationType isEqualToString:SPUInstallationTypeApplication]);
                    
                    success = [_updateValidator validateDownloadPathWithFallbackOnCodeSigning:fallbackOnCodeSigning error:&prevalidationError];
                }
            } else {
                success = YES;
            }
        }
    }
    
    if (!success) {
        [self unarchiverDidFailWithError:prevalidationError];
    } else {
        [unarchiver
         unarchiveWithCompletionBlock:^(NSError * _Nullable error) {
             if (error != nil) {
                 [self unarchiverDidFailWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Failed to unarchive %@", archivePath], NSUnderlyingErrorKey: (NSError * _Nonnull)error }]];
             } else {
                 [self->_communicator handleMessageWithIdentifier:SPUValidationStarted data:[NSData data]];
                 
                 NSError *validationError = nil;
                 BOOL validationSuccess = [self->_updateValidator validateWithUpdateDirectory:self->_extractionDirectory error:&validationError];
                 
                 if (!validationSuccess) {
                     [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Update validation was a failure", NSUnderlyingErrorKey: validationError }]];
                 } else {
                     [self->_communicator handleMessageWithIdentifier:SPUInstallationStartedStage1 data:[NSData data]];
                     
                     self->_finishedValidation = YES;
                     if (self->_agentInitiatedConnection) {
                         [self retrieveProcessIdentifierAndStartInstallation];
                     }
                 }
             }
         }
         progressBlock:^(double progress) {
             if (sizeof(progress) == sizeof(uint64_t)) {
                 uint64_t progressValue = CFSwapInt64HostToLittle(*(uint64_t *)&progress);
                 NSData *data = [NSData dataWithBytes:&progressValue length:sizeof(progressValue)];
                 
                 [self->_communicator handleMessageWithIdentifier:SPUExtractedArchiveWithProgress data:data];
             }
         } waitForCleanup:NO];
    }
}

- (void)clearUpdateDirectory SPU_OBJC_DIRECT
{
    if (_updateDirectoryPath != nil) {
        NSError *theError = nil;
        if (![[[SUFileManager alloc] init] removeItemAtURL:[NSURL fileURLWithPath:_updateDirectoryPath] error:&theError]) {
            SULog(SULogLevelError, @"Couldn't remove update folder: %@.", theError);
        }
        _updateDirectoryPath = nil;
    }
}

- (void)unarchiverDidFailWithError:(NSError *)error SPU_OBJC_DIRECT
{
    SULog(SULogLevelError, @"Failed to unarchive file");
    SULogError(error);
    
    // No longer need update validator until next possible extraction (eg: if initial delta update fails)
    _updateValidator = nil;
    
    // Client could try update again with different inputs
    // Eg: one common case is if a delta update fails, client may want to fall back to regular update
    // We really only need to set updateDirectoryPath to nil since that's the field we check if we've received installation data,
    // but may as well set other fields to nil too
    [self clearUpdateDirectory];
    _downloadName = nil;
    _extractionDirectory = nil;
    _decryptionPassword = nil;
    _signatures = nil;
    _relaunchPath = nil;
    _host = nil;
    
    NSData *archivedError = SPUArchiveRootObjectSecurely(error);
    [_communicator handleMessageWithIdentifier:SPUArchiveExtractionFailed data:archivedError != nil ? archivedError : [NSData data]];
}

- (void)agentConnectionDidInitiate
{
    _agentInitiatedConnection = YES;
    if (_finishedValidation) {
        [self retrieveProcessIdentifierAndStartInstallation];
    }
}

- (void)agentConnectionDidInvalidate
{
    if (!_finishedValidation || !_agentInitiatedConnection || !_targetTerminated) {
        NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:@{ NSLocalizedDescriptionKey: @"Error: Agent connection invalidated before installation began" }];
        
        NSError *agentError = _agentConnection.invalidationError;
        if (agentError != nil) {
            userInfo[NSUnderlyingErrorKey] = agentError;
        }
        
        [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:userInfo]];
    }
}

- (void)retrieveProcessIdentifierAndStartInstallation SPU_OBJC_DIRECT
{
    // We use the relaunch path for the bundle to listen for termination instead of the host path
    // For a plug-in this makes a big difference; we want to wait until the app hosting the plug-in terminates
    // Otherwise for an app, the relaunch path and host path should be identical
    
    __block BOOL receivedResponse = NO;
    [_agentConnection.agent registerApplicationBundlePath:_relaunchPath reply:^(BOOL targetTerminated) {
        dispatch_async(dispatch_get_main_queue(), ^{
            receivedResponse = YES;
            
            if (!targetTerminated) {
                [self->_agentConnection.agent listenForTerminationWithCompletion:^{
                    dispatch_async(dispatch_get_main_queue(), ^{
                        self->_targetTerminated = YES;
                        
                        if (self->_performedStage1Installation) {
                            [self finishInstallationAfterHostTermination];
                        }
                    });
                }];
            } else {
                self->_targetTerminated = YES;
            }
            
            [self startInstallation];
        });
    }];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(RETRIEVE_PROCESS_IDENTIFIER_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!receivedResponse) {
            [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Timeout error: failed to retrieve process identifier from agent" }]];
        }
    });
}

- (void)handleMessageWithIdentifier:(int32_t)identifier data:(NSData *)data
{
    if (identifier == SPUInstallationData && _updateDirectoryPath == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Mark that we have received the installation data
            // Do not rely on eg: self->_updateDirectoryPath != nil because we may set it to nil again if an early stage fails (i.e, archive extraction)
            self->_receivedInstallationData = YES;
            
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
            if (bundleIdentifier == nil || ![bundleIdentifier isEqualToString:self->_hostBundleIdentifier]) {
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Error: Failed to match host bundle identifiers %@ and %@", self->_hostBundleIdentifier, bundleIdentifier] }]];
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
            
            // Resolve the bookmark data for the downloaded update
            // See "Share file access between processes with URL bookmarks" in https://developer.apple.com/documentation/security/app_sandbox/accessing_files_from_the_macos_app_sandbox
            BOOL isStale = NO;
            NSError *bookmarkError = nil;
            NSURL *downloadURL = [NSURL URLByResolvingBookmarkData:installationData.updateURLBookmarkData options:NSURLBookmarkResolutionWithoutUI relativeToURL:nil bookmarkDataIsStale:&isStale error:&bookmarkError];
            if (downloadURL == nil) {
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Error: Failed to resolve bookmark data from downloaded update", NSUnderlyingErrorKey: bookmarkError }]];
                
                return;
            }
            
            // Validate the download URL before moving it
            {
                NSArray<NSString *> *downloadURLPathComponents = downloadURL.URLByResolvingSymlinksInPath.pathComponents;
                if (downloadURLPathComponents == nil) {
                    [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Error: Failed to retrieve path components from download URL" }]];
                    
                    return;
                }
                
                if ([downloadURLPathComponents containsObject:@".."]) {
                    [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Error: download URL path components contains '..' which is unsafe" }]];
                    
                    return;
                }
                
                if (![downloadURLPathComponents containsObject:@SPARKLE_BUNDLE_IDENTIFIER] || ![downloadURLPathComponents containsObject:@"PersistentDownloads"]) {
                    [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Error: download URL path components does not contain PersistentDownloads or "@SPARKLE_BUNDLE_IDENTIFIER }]];
                    
                    return;
                }
            }
            
            if (!isStale) {
                SULog(SULogLevelError, @"Error: bookmark data for update download is stale.. but still continuing.");
            }
            
            NSString *originalDownloadName = downloadURL.lastPathComponent;
            if (originalDownloadName == nil) {
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Error: Failed to retrieve download name from download URL" }]];
                
                return;
            }
            
            // Randomize the download name if possible
            // This adds better security if there are any vulnerabilities in extracting/executing archives
            // which allow writing in unexpected locations. For zip/tar/dmg archives we may also extract them before
            // performing signing validation (due to key rotation).
            NSString *downloadName;
            NSString *randomizedUUIDString = [[NSUUID UUID] UUIDString];
            if (randomizedUUIDString != nil) {
                // Find the real path extension of the download name
                // We cannot use -[NSString pathExtension] because it may not give us the full path extension
                // E.g. for "foo.tar.xz" we need "tar.xz", not "xz"
                NSString *downloadPathExtension;
                NSRange pathExtensionDelimiterRange = [originalDownloadName rangeOfString:@"."];
                if (pathExtensionDelimiterRange.location == NSNotFound) {
                    downloadPathExtension = @"";
                } else {
                    downloadPathExtension = [originalDownloadName substringFromIndex:pathExtensionDelimiterRange.location + 1];
                }
                
                NSString *randomizedDownloadName = [randomizedUUIDString stringByAppendingPathExtension:downloadPathExtension];
                if (randomizedDownloadName != nil) {
                    downloadName = randomizedDownloadName;
                } else {
                    downloadName = originalDownloadName;
                }
            } else {
                downloadName = originalDownloadName;
            }
            
            // Move the download archive to somewhere where probably only we will be touching it
            // This prevents eg: if a bug exists in the updater that removes files we are trying to install
            // When this tool is ran as root, we are moving it into a directory that only root will have access to
            
            NSURL *downloadDestinationURL = [[NSURL fileURLWithPath:cacheInstallationPath] URLByAppendingPathComponent:downloadName];
            
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
            
            NSString *extractionDirectory = [SPULocalCacheDirectory createUniqueDirectoryInDirectory:cacheInstallationPath];
            if (extractionDirectory == nil) {
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Error: Failed to create installation extraction directory in %@", cacheInstallationPath] }]];
                
                return;
            }
            
            // Carry these properties separately rather than using the SUInstallationInputData object
            // Some of our properties may slightly differ than our input and we don't want to make the mistake of using one of those
            self->_installationType = installationType;
            self->_relaunchPath = installationData.relaunchPath;
            self->_downloadName = downloadName;
            self->_signatures = installationData.signatures;
            self->_updateDirectoryPath = cacheInstallationPath;
            self->_extractionDirectory = extractionDirectory;
            self->_decryptionPassword = installationData.decryptionPassword;
            self->_host = [[SUHost alloc] initWithBundle:hostBundle];
            self->_verifierInformation = [[SPUVerifierInformation alloc] initWithExpectedVersion:installationData.expectedVersion expectedContentLength:installationData.expectedContentLength];
            
            [self extractAndInstallUpdate];
        });
    } else if (identifier == SPUSentUpdateAppcastItemData) {
        SUAppcastItem *updateItem = (SUAppcastItem *)SPUUnarchiveRootObjectSecurely(data, [SUAppcastItem class]);
        if (updateItem != nil) {
            SPUInstallationInfo *installationInfo = [[SPUInstallationInfo alloc] initWithAppcastItem:updateItem canSilentlyInstall:[_installer canInstallSilently]];
            
            NSData *archivedData = SPUArchiveRootObjectSecurely(installationInfo);
            if (archivedData != nil) {
                [_agentConnection.agent registerInstallationInfoData:archivedData];
            }
        }
    } else if (identifier == SPUResumeInstallationToStage2 && data.length == sizeof(uint8_t) * 2) {
        // Because anyone can ask us to resume the installation, it may be wise to think about backwards compatibility here if IPC changes
        uint8_t relaunch = *((const uint8_t *)data.bytes);
        uint8_t showsUI = *((const uint8_t *)data.bytes + 1);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // This flag has an impact on interactive type installations and showing UI progress during non-interactive installations
            self->_shouldShowUI = (BOOL)showsUI;
            // Don't test if the application was alive initially, leave that to the progress agent if we decide to relaunch
            self->_shouldRelaunch = (BOOL)relaunch;
            
            if (self->_performedStage1Installation) {
                // Resume the installation if we aren't done with stage 2 yet, and remind the client we are prepared to relaunch
                dispatch_async(self->_installerQueue, ^{
                    if (!self->_performedStage2Installation) {
                        [self performStage2Installation];
                    } else if (!self->_performedStage3Installation) {
                        // If we already performed the 2nd stage, re-purpose this request to re-try sending another termination signal
                        dispatch_async(dispatch_get_main_queue(), ^{
                            // Don't check if the target is already terminated, leave that to the progress agent
                            // We could be slightly off if there were multiple instances running
                            [self->_agentConnection.agent sendTerminationSignal];
                        });
                    }
                });
            }
        });
    } else if (identifier == SPUCancelInstallation) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self cleanupAndExitWithStatus:0 error:nil];
        });
    } else if (identifier == SPUUpdaterAlivePong) {
        _receivedUpdaterPong = YES;
    }
}

- (void)startInstallation SPU_OBJC_DIRECT
{
    _willCompleteInstallation = YES;
    
    dispatch_queue_attr_t queuePriority = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
    
    _installerQueue = dispatch_queue_create("org.sparkle-project.sparkle.installer", queuePriority);
    
    dispatch_async(_installerQueue, ^{
        NSError *installerError = nil;
        id <SUInstallerProtocol> installer = [SUInstaller installerForHost:self->_host expectedInstallationType:self->_installationType updateDirectory:self->_extractionDirectory homeDirectory:self->_homeDirectory userName:self->_userName error:&installerError];
        
        if (installer == nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Error: Failed to create installer instance", NSUnderlyingErrorKey: installerError }]];
            });
            return;
        }
        
        NSError *firstStageError = nil;
        if (![installer performInitialInstallation:&firstStageError]) {
            self->_installer = nil;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Error: Failed to start installer", NSUnderlyingErrorKey: firstStageError }]];
            });
            return;
        }
        
        uint8_t canPerformSilentInstall = (uint8_t)[installer canInstallSilently];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_installer = installer;
            
            uint8_t sendInformation[] = {canPerformSilentInstall, (uint8_t)self->_targetTerminated};
            
            NSData *sendData = [NSData dataWithBytes:sendInformation length:sizeof(sendInformation)];
            
            [self->_communicator handleMessageWithIdentifier:SPUInstallationFinishedStage1 data:sendData];
            
            self->_performedStage1Installation = YES;
            
            if (self->_targetTerminated) {
                // Stage 2 can still be run before we finish installation
                // if the updater requests for it before the app is terminated
                [self finishInstallationAfterHostTermination];
            }
        });
    });
}

- (void)performStage2Installation SPU_OBJC_DIRECT
{
    BOOL canPerformSecondStage = _shouldShowUI || [_installer canInstallSilently];
    if (canPerformSecondStage) {
        _performedStage2Installation = YES;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            uint8_t targetTerminated = (uint8_t)self->_targetTerminated;
            
            NSData *sendData = [NSData dataWithBytes:&targetTerminated length:sizeof(targetTerminated)];
            [self->_communicator handleMessageWithIdentifier:SPUInstallationFinishedStage2 data:sendData];
            
            // Don't check if the target is already terminated, leave that to the progress agent
            // We could be slightly off if there were multiple instances running
            [self->_agentConnection.agent sendTerminationSignal];
        });
    } else {
        _installer = nil;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Error: Failed to resume installer on stage 2 because installation cannot be installed silently" }]];
        });
    }
}

- (void)finishInstallationAfterHostTermination SPU_OBJC_DIRECT
{
    assert(self->_targetTerminated);
    
    // Show our installer progress UI tool if only after a certain amount of time passes,
    // and if our installer is silent (i.e, doesn't show progress on its own)
    __block BOOL shouldShowUIProgress = YES;
    if (self->_shouldShowUI && [self->_installer canInstallSilently]) {
        // Ask the updater if it is still alive
        // If they are, we will receive a pong response back
        // Reset if we received a pong just to be on the safe side
        self->_receivedUpdaterPong = NO;
        [self->_communicator handleMessageWithIdentifier:SPUUpdaterAlivePing data:[NSData data]];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SUDisplayProgressTimeDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // Make sure we're still eligible for showing the installer progress
            // Also if the updater process is still alive, showing the progress should not be our duty
            // if the communicator object is nil, the updater definitely isn't alive. However, if it is not nil,
            // this does not necessarily mean the updater is alive, so we should also check if we got a recent response back from the updater
            if (shouldShowUIProgress && (!self->_receivedUpdaterPong || self->_communicator == nil)) {
                [self->_agentConnection.agent showProgress];
            }
        });
    }
        
    dispatch_async(self->_installerQueue, ^{
        if (!self->_performedStage2Installation) {
            [self performStage2Installation];
        }
        
        if (!self->_performedStage2Installation) {
            // We failed and we're going to exit shortly
            return;
        }
        
        NSError *thirdStageError = nil;
        if (![self->_installer performFinalInstallationProgressBlock:nil error:&thirdStageError]) {
            [self->_installer performCleanup];
            self->_installer = nil;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SPUInstallerError userInfo:@{ NSLocalizedDescriptionKey: @"Failed to finalize installation", NSUnderlyingErrorKey: thirdStageError }]];
            });
            return;
        }
        
        self->_performedStage3Installation = YES;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Make sure to stop our displayed progress before we move onto cleanup & relaunch
            // This will also stop the agent from broadcasting the status info service, which we want to do before
            // we relaunch the app because the relaunched app could check the service upon launch..
            [self->_agentConnection.agent stopProgress];
            shouldShowUIProgress = NO;
            
            [self->_communicator handleMessageWithIdentifier:SPUInstallationFinishedStage3 data:[NSData data]];
            
            if (self->_shouldRelaunch) {
                // This will also signal to the agent that it will terminate soon
                [self->_agentConnection.agent relaunchApplication];
            }
            
            [self->_installer performCleanup];
            
            [self cleanupAndExitWithStatus:EXIT_SUCCESS error:nil];
        });
    });
}

- (void)cleanupAndExitWithStatus:(int)status error:(NSError * _Nullable)error __attribute__((noreturn))
{
    if (error != nil) {
        SULogError(error);
        
        NSData *errorData = SPUArchiveRootObjectSecurely((NSError * _Nonnull)error);
        if (errorData != nil) {
            [_communicator handleMessageWithIdentifier:SPUInstallerError data:errorData];
        }
    }
    
    // It's nice to tell the other end we're invalidating
    
    [_activeConnection invalidate];
    _activeConnection = nil;
    
    [_xpcListener invalidate];
    _xpcListener = nil;
    
    [_agentConnection invalidate];
    _agentConnection = nil;
    
    [self clearUpdateDirectory];
    
    exit(status);
}

@end
