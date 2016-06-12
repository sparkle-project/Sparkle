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
#import "SULog.h"
#import "SUHost.h"
#import "SULocalizations.h"
#import "SUStandardVersionComparator.h"
#import "SUDSAVerifier.h"
#import "SUCodeSigningVerifier.h"
#import "SURemoteMessagePort.h"
#import "SULocalMessagePort.h"
#import "SUMessageTypes.h"
#import "SUSecureCoding.h"
#import "SUInstallationInputData.h"
#import "SUUnarchiver.h"
#import "SUFileManager.h"
#import "SUInstallationInfo.h"
#import "SUAppcastItem.h"
#import "SUAuthorizationEnvironment.h"
#import "SUApplicationInfo.h"
#import "SUErrors.h"

/*!
 * Terminate the application after a delay from launching the new update to avoid OS activation issues
 * This delay should be be high enough to increase the likelihood that our updated app will be launched up front,
 * but should be low enough so that the user doesn't ponder why the updater hasn't finished terminating yet
 */
static const NSTimeInterval SUTerminationTimeDelay = 0.5;

/*!
 * Show display progress UI after a delay from starting the final part of the installation.
 * This should be long enough so that we don't show progress for very fast installations, but
 * short enough so that we don't leave the user wondering why nothing is happening.
 */
static const NSTimeInterval SUDisplayProgressTimeDelay = 0.7;

@interface AppInstaller ()

@property (nonatomic, strong) TerminationListener *terminationListener;

@property (nonatomic, readonly, copy) NSString *hostBundleIdentifier;
@property (nonatomic, readonly) BOOL inheritsPrivileges;
@property (nonatomic) SUHost *host;
@property (nonatomic) SULocalMessagePort *localPort;
@property (nonatomic) SURemoteMessagePort *remotePort;
@property (nonatomic) SUInstallationInputData *installationData;
@property (nonatomic, assign) BOOL shouldRelaunch;
@property (nonatomic, assign) BOOL shouldShowUI;
@property (nonatomic) NSData *installationInfoData;

@property (nonatomic) id<SUInstallerProtocol> installer;
@property (nonatomic) BOOL willCompleteInstallation;

@property (nonatomic) dispatch_queue_t installerQueue;
@property (nonatomic) BOOL performedStage1Installation;
@property (nonatomic) BOOL performedStage2Installation;
@property (nonatomic) BOOL performedStage3Installation;

@end

@implementation AppInstaller

@synthesize hostBundleIdentifier = _hostBundleIdentifier;
@synthesize inheritsPrivileges = _inheritsPrivileges;
@synthesize terminationListener = _terminationListener;
@synthesize localPort = _localPort;
@synthesize remotePort = _remotePort;
@synthesize host = _host;
@synthesize installationData = _installationData;
@synthesize shouldRelaunch = _shouldRelaunch;
@synthesize shouldShowUI = _shouldShowUI;
@synthesize installationInfoData = _installationInfoData;
@synthesize installer = _installer;
@synthesize willCompleteInstallation = _willCompleteInstallation;
@synthesize installerQueue = _installerQueue;
@synthesize performedStage1Installation = _performedStage1Installation;
@synthesize performedStage2Installation = _performedStage2Installation;
@synthesize performedStage3Installation = _performedStage3Installation;

/*
 * hostPath - path to host (original) application
 * relaunchPath - path to what the host wants to relaunch (default is same as hostPath)
 * hostProcessIdentifier - process identifier of the host before launching us
 * updateFolderPath - path to update folder (i.e, temporary directory containing the new update archive)
 * downloadPath - path to new downloaded update archive
 * shouldRelaunch - indicates if the new installed app should re-launched
 * shouldShowUI - indicates if we should show the status window when installing the update
 */

- (instancetype)initWithHostBundleIdentifier:(NSString *)hostBundleIdentifier inheritsPrivileges:(BOOL)inheritsPrivileges
{
    if (!(self = [super init])) {
        return nil;
    }
    
    _hostBundleIdentifier = [hostBundleIdentifier copy];
    
    _inheritsPrivileges = inheritsPrivileges;
    
    self.localPort =
    [[SULocalMessagePort alloc]
     initWithServiceName:SUAutoUpdateServiceNameForBundleIdentifier(hostBundleIdentifier)
     messageCallback:^NSData *(int32_t identifier, NSData * _Nonnull data) {
         return [self handleMessageWithIdentifier:identifier data:data];
     }
     invalidationCallback:^{
         dispatch_async(dispatch_get_main_queue(), ^{
             if (self.localPort != nil) {
                 [self cleanupAndExitWithStatus:EXIT_FAILURE];
             }
         });
     }];
    
    if (self.localPort == nil) {
        SULog(@"Failed creating local message port from installer");
        [self cleanupAndExitWithStatus:EXIT_FAILURE];
    }
    
    [self startRemotePortWithCompletion:^(BOOL success) {
        if (!success) {
            SULog(@"Failed creating remote message port from installer");
            [self cleanupAndExitWithStatus:EXIT_FAILURE];
        }
    }];
    
    return self;
}

- (void)startRemotePortWithCompletion:(void (^)(BOOL))completionHandler
{
    if (self.remotePort != nil) {
        completionHandler(YES);
        return;
    }
    
    self.remotePort = [[SURemoteMessagePort alloc] initWithServiceName:SUUpdateDriverServiceNameForBundleIdentifier(self.hostBundleIdentifier)];
    
    __weak AppInstaller *weakSelf = self;
    [self.remotePort connectWithLookupCompletion:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completionHandler(success);
            
            if (success) {
                [weakSelf.remotePort setInvalidationHandler:^{
                    dispatch_async(dispatch_get_main_queue(), ^{
                        AppInstaller *strongSelf = weakSelf;
                        if (strongSelf != nil) {
                            if (strongSelf.remotePort != nil && !strongSelf.willCompleteInstallation) {
                                SULog(@"Invalidation on remote port being called, and installation is not close enough to completion!");
                                [strongSelf cleanupAndExitWithStatus:EXIT_FAILURE];
                            }
                            strongSelf.remotePort = nil;
                        }
                    });
                }];
            }
        });
    }];
}

/**
 * If the update is a package, then the download must be signed using DSA. No other verification is done.
 *
 * If the update is a bundle, then the download must also be signed using DSA.
 * However, a change of DSA public keys is allowed if the Apple Code Signing identities match and are valid.
 * Likewise, a change of Apple Code Signing identities is allowed if the DSA public keys match and the update is valid.
 *
 */
#warning - This might be better part of SUInstaller protocol since validation between app & packages differ
- (BOOL)validateUpdateForHost:(SUHost *)host downloadedToPath:(NSString *)downloadedPath extractedToPath:(NSString *)extractedPath DSASignature:(NSString *)DSASignature
{
    BOOL isPackage = NO;
    NSString *installSourcePath = [SUInstaller installSourcePathInUpdateFolder:extractedPath forHost:host isPackage:&isPackage isGuided:NULL];
    if (installSourcePath == nil) {
        SULog(@"No suitable install is found in the update. The update will be rejected.");
        return NO;
    }
    
    NSString *publicDSAKey = host.publicDSAKey;
    
    // Modern packages are not distributed as bundles and are code signed differently than regular applications
    if (isPackage) {
        if (nil == publicDSAKey) {
            SULog(@"The existing app bundle does not have a DSA key, so it can't verify installer packages.");
        }
        
        BOOL packageValidated = [SUDSAVerifier validatePath:downloadedPath withEncodedDSASignature:DSASignature withPublicDSAKey:publicDSAKey];
        
        if (!packageValidated) {
            SULog(@"DSA signature validation of the package failed. The update contains an installer package, and valid DSA signatures are mandatory for all installer packages. The update will be rejected. Sign the installer with a valid DSA key or use an .app bundle update instead.");
        }
        
        return packageValidated;
    }
    
    NSBundle *newBundle = [NSBundle bundleWithPath:installSourcePath];
    if (newBundle == nil) {
        SULog(@"No suitable bundle is found in the update. The update will be rejected.");
        return NO;
    }
    
    SUHost *newHost = [[SUHost alloc] initWithBundle:newBundle];
    NSString *newPublicDSAKey = newHost.publicDSAKey;
    
    if (newPublicDSAKey == nil) {
        SULog(@"No public DSA key is found in the update. For security reasons, the update will be rejected.");
        return NO;
    }
    
    BOOL dsaKeysMatch = (publicDSAKey == nil) ? NO : [publicDSAKey isEqualToString:newPublicDSAKey];
    
    if (![SUDSAVerifier validatePath:downloadedPath withEncodedDSASignature:DSASignature withPublicDSAKey:newPublicDSAKey]) {
        SULog(@"DSA signature validation failed. The update has a public DSA key and is signed with a DSA key, but the %@ doesn't match the signature. The update will be rejected.",
              dsaKeysMatch ? @"public key" : @"new public key shipped with the update");
        return NO;
    }
    
    BOOL updateIsCodeSigned = [SUCodeSigningVerifier bundleAtPathIsCodeSigned:installSourcePath];
    
    if (dsaKeysMatch) {
        NSError *error = nil;
        if (updateIsCodeSigned && ![SUCodeSigningVerifier codeSignatureIsValidAtPath:installSourcePath error:&error]) {
            SULog(@"The update archive has a valid DSA signature, but the app is also signed with Code Signing, which is corrupted: %@. The update will be rejected.", error);
            return NO;
        }
    } else {
        NSString *hostBundlePath = host.bundlePath;
        BOOL hostIsCodeSigned = [SUCodeSigningVerifier bundleAtPathIsCodeSigned:hostBundlePath];
        
        NSString *dsaStatus = newPublicDSAKey ? @"has a new DSA key that doesn't match the previous one" : (publicDSAKey ? @"removes the DSA key" : @"isn't signed with a DSA key");
        if (!hostIsCodeSigned || !updateIsCodeSigned) {
            NSString *acsStatus = !hostIsCodeSigned ? @"old app hasn't been signed with app Code Signing" : @"new app isn't signed with app Code Signing";
            SULog(@"The update archive %@, and the %@. At least one method of signature verification must be valid. The update will be rejected.", dsaStatus, acsStatus);
            return NO;
        }
        
        NSError *error = nil;
        if (![SUCodeSigningVerifier codeSignatureAtPath:hostBundlePath matchesSignatureAtPath:installSourcePath error:&error]) {
            SULog(@"The update archive %@, and the app is signed with a new Code Signing identity that doesn't match code signing of the original app: %@. At least one method of signature verification must be valid. The update will be rejected.", dsaStatus, error);
            return NO;
        }
    }
    
    return YES;
}

- (void)start
{
    [self.remotePort sendMessageWithIdentifier:SURequestInstallationParameters data:[NSData data] completion:^(BOOL success) {
        if (!success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                SULog(@"Error: Failed to send request for installation parameters");
                [self cleanupAndExitWithStatus:EXIT_FAILURE];
            });
        }
    }];
}

- (void)extractAndInstallUpdate
{
    NSString *downloadPath = [self.installationData.updateDirectoryPath stringByAppendingPathComponent:self.installationData.downloadName];
    id <SUUnarchiverProtocol> unarchiver = [SUUnarchiver unarchiverForPath:downloadPath updatingHostBundlePath:self.host.bundlePath decryptionPassword:self.installationData.decryptionPassword delegate:self];
    if (!unarchiver) {
        SULog(@"Error: No valid unarchiver for %@!", downloadPath);
        [self unarchiverDidFail];
    } else {
        [unarchiver start];
    }
}

- (void)unarchiverExtractedProgress:(double)progress
{
    if (sizeof(progress) == sizeof(uint64_t)) {
        uint64_t progressValue = CFSwapInt64HostToLittle(*(uint64_t *)&progress);
        NSData *data = [NSData dataWithBytes:&progressValue length:sizeof(progressValue)];
        [self.remotePort sendMessageWithIdentifier:SUExtractedArchiveWithProgress data:data completion:^(BOOL success) {
            if (!success) {
                SULog(@"Error sending extracted progress");
            }
        }];
    }
}

- (void)unarchiverDidFail
{
    // Client could try update again with different inputs
    // Eg: one common case is if a delta update fails, client may want to fall back to regular update
    self.installationData = nil;
    
    [self.remotePort sendMessageWithIdentifier:SUArchiveExtractionFailed data:[NSData data] completion:^(BOOL success) {
        if (!success) {
            SULog(@"Error sending extraction failed");
        }
    }];
}

- (void)unarchiverDidFinish
{
    [self.remotePort sendMessageWithIdentifier:SUValidationStarted data:[NSData data] completion:^(BOOL success) {
        if (!success) {
            SULog(@"Error sending validation finish");
        }
    }];
    
    NSString *downloadPath = [self.installationData.updateDirectoryPath stringByAppendingPathComponent:self.installationData.downloadName];
    BOOL validationSuccess = [self validateUpdateForHost:self.host downloadedToPath:downloadPath extractedToPath:self.installationData.updateDirectoryPath DSASignature:self.installationData.dsaSignature];
    
    if (!validationSuccess) {
        SULog(@"Error: update validation was a failure");
        [self cleanupAndExitWithStatus:EXIT_FAILURE];
    } else {
        [self.remotePort sendMessageWithIdentifier:SUInstallationStartedStage1 data:[NSData data] completion:^(BOOL success) {
            if (!success) {
                SULog(@"Error sending stage 1 started");
            }
        }];
        
        [self startInstallation];
    }
}

- (NSData *)handleMessageWithIdentifier:(int32_t)identifier data:(NSData *)data
{
    NSData *replyData = nil;
    
    if (identifier == SUInstallationData && self.installationData == nil) {
        dispatch_async(dispatch_get_main_queue(), ^{
            SUInstallationInputData *installationData = (SUInstallationInputData *)SUUnarchiveRootObjectSecurely(data, [SUInstallationInputData class]);
            if (installationData == nil) {
                SULog(@"Error: Failed to unarchive input installation data");
                [self cleanupAndExitWithStatus:EXIT_FAILURE];
            } else {
                SUInstallationInputData *nonNullInstallationData = installationData;
                NSBundle *hostBundle = [NSBundle bundleWithPath:nonNullInstallationData.hostBundlePath];
                SUHost *host = [[SUHost alloc] initWithBundle:hostBundle];
                
                NSString *bundleIdentifier = hostBundle.bundleIdentifier;
                if (bundleIdentifier == nil || ![bundleIdentifier isEqualToString:self.hostBundleIdentifier]) {
                    SULog(@"Error: Failed to match host bundle identifiers %@ and %@", self.hostBundleIdentifier, bundleIdentifier);
                    [self cleanupAndExitWithStatus:EXIT_FAILURE];
                } else {
                    NSBundle *relaunchBundle = [NSBundle bundleWithPath:nonNullInstallationData.relaunchPath];
                    if (relaunchBundle == nil) {
                        SULog(@"Error: Failed to locate relaunch bundle path %@", nonNullInstallationData.relaunchPath);
                        [self cleanupAndExitWithStatus:EXIT_FAILURE];
                    } else {
                        self.host = host;
                        self.installationData = installationData;
                        
                        // We use the relaunch path for the bundle to listen for termination instead of the host path
                        // For a plug-in this makes a big difference; we want to wait until the app hosting the plug-in terminates
                        // Otherwise for an app, the relaunch path and host path should be identical
                        self.terminationListener = [[TerminationListener alloc] initWithBundle:relaunchBundle];
                        
                        [self extractAndInstallUpdate];
                    }
                }
            }
        });
    } else if (identifier == SUSentUpdateAppcastItemData) {
        if (self.installationInfoData == nil) {
            SUAppcastItem *updateItem = (SUAppcastItem *)SUUnarchiveRootObjectSecurely(data, [SUAppcastItem class]);
            if (updateItem != nil) {
                SUInstallationInfo *installationInfo = [[SUInstallationInfo alloc] initWithAppcastItem:updateItem canSilentlyInstall:[self.installer canInstallSilently]];
                
                self.installationInfoData = SUArchiveRootObjectSecurely(installationInfo);
            }
        }
    } else if (identifier == SUReceiveUpdateAppcastItemData) {
        replyData = self.installationInfoData;
    } else if (identifier == SUResumeInstallationToStage2 && data.length == sizeof(uint8_t) * 2) {
        uint8_t relaunch = *((const uint8_t *)data.bytes);
        uint8_t showsUI = *((const uint8_t *)data.bytes + 1);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Only applicable to stage 2
            self.shouldShowUI = (BOOL)showsUI;
            
            // Allow handling if we should relaunch at any time
            self.shouldRelaunch = (BOOL)relaunch;
            
#warning todo: handle this message even if we aren't ready for stage 2 yet.
            // We should try re-creating the remote port if necessary, in case the client has
            // restarted since and wants a reply back when we say it's OK to terminate the app
            [self startRemotePortWithCompletion:^(BOOL success) {
                if (!success) {
                    SULog(@"Installer failed to set up remote port to updater before resuming installation");
                }
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (self.performedStage1Installation) {
                        // Resume the installation if we aren't done with stage 2 yet, and remind the client we are prepared to relaunch
                        dispatch_async(self.installerQueue, ^{
                            [self performStage2InstallationIfNeeded];
                        });
                    }
                });
            }];
        });
    }
    
    return replyData;
}

- (void)startInstallation
{
    self.willCompleteInstallation = YES;
    
    self.installerQueue = dispatch_queue_create("org.sparkle-project.sparkle.installer", DISPATCH_QUEUE_SERIAL);
    
    dispatch_async(self.installerQueue, ^{
        NSError *installerError = nil;
        id <SUInstallerProtocol> installer = [SUInstaller installerForHost:self.host updateDirectory:self.installationData.updateDirectoryPath versionComparator:[SUStandardVersionComparator standardVersionComparator] error:&installerError];
        
        if (installer == nil) {
            SULog(@"Error: Failed to create installer instance with error: %@", installerError);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self cleanupAndExitWithStatus:EXIT_FAILURE];
            });
            return;
        }
        
        NSError *firstStageError = nil;
        if (![installer performFirstStage:&firstStageError]) {
            SULog(@"Error: Failed to start installer with error: %@", firstStageError);
            [self.installer cleanup];
            self.installer = nil;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self cleanupAndExitWithStatus:EXIT_FAILURE];
            });
            return;
        }
        
        uint8_t canPerformSilentInstall = (uint8_t)[installer canInstallSilently];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.installer = installer;
            
            uint8_t targetTerminated = (uint8_t)self.terminationListener.terminated;
            
            uint8_t sendInformation[] = {canPerformSilentInstall, targetTerminated};
            
            NSData *sendData = [NSData dataWithBytes:sendInformation length:sizeof(sendInformation)];
            
            [self.remotePort sendMessageWithIdentifier:SUInstallationFinishedStage1 data:sendData completion:^(BOOL success) {
                if (!success) {
                    SULog(@"Error sending stage 1 finish");
                    [self cleanupAndExitWithStatus:EXIT_FAILURE];
                }
            }];
            
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
    
    SUAuthorizationEnvironment *environment = nil;
    NSURL *tempIconDirectoryURL = nil;
    if (self.shouldShowUI && !self.inheritsPrivileges && [self.installer mayNeedToRequestAuthorization]) {
        NSString *prompt = [NSString stringWithFormat:NSLocalizedString(@"%1$@ wants to update.", nil), self.host.name];
        
        NSString *iconPath = nil;
        
        // Authorization API requires a 32x32 icon image and accepts png (but not icns or tiff)
        NSImage *icon = [SUApplicationInfo bestIconForBundle:self.host.bundle];
        [icon setSize:NSMakeSize(32, 32)];
        
        CGImageRef iconRef = [icon CGImageForProposedRect:NULL context:nil hints:nil];
        NSBitmapImageRep *representation = [[NSBitmapImageRep alloc] initWithCGImage:iconRef];
        NSData *pngData = [representation representationUsingType:NSPNGFileType properties:@{}];
        
        // Write the icon to a temporary directory. This icon file should be in a directory that's readable to everyone.
        NSError *tempError = nil;
        tempIconDirectoryURL = [[SUFileManager defaultManager] makeTemporaryDirectoryWithPreferredName:@"sparkle-auth-icon" appropriateForDirectoryURL:[NSURL fileURLWithPath:NSTemporaryDirectory()] error:&tempError];
        if (tempIconDirectoryURL == nil) {
            SULog(@"Failed to create temporary directory for authorization icon: %@", tempError);
        } else {
            NSURL *iconURL = [tempIconDirectoryURL URLByAppendingPathComponent:@"icon.png"];
            if ([pngData writeToURL:iconURL atomically:YES]) {
                iconPath = iconURL.path;
            }
        }
        
        environment = [[SUAuthorizationEnvironment alloc] initWithPrompt:prompt iconPath:(iconPath != nil ? iconPath : @"")];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // We should activate our app so that the auth prompt will be active
            [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
        });
    }
    
    NSString *fileOperationToolPath = [[[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@""SPARKLE_FILEOP_TOOL_NAME];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:fileOperationToolPath]) {
        SULog(@"Potential Installation Error: File operation tool path %@ is not found", fileOperationToolPath);
    }
    
    NSError *secondStageError = nil;
    BOOL performedSecondStage = [self.installer performSecondStageAllowingAuthorization:!self.inheritsPrivileges fileOperationToolPath:fileOperationToolPath environment:environment allowingUI:self.shouldShowUI error:&secondStageError];
    
    if (tempIconDirectoryURL != nil) {
        [[SUFileManager defaultManager] removeItemAtURL:tempIconDirectoryURL error:NULL];
    }
    
    if (performedSecondStage) {
        self.performedStage2Installation = YES;
    }
    
    void (^cleanupAndExit)(void) = ^{
        SULog(@"Error: Failed to resume installer on stage 2 with error: %@", secondStageError);
        [self.installer cleanup];
        self.installer = nil;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self cleanupAndExitWithStatus:EXIT_FAILURE];
        });
    };
    
    // Let the other end know we cancelled so they can fail gracefully without disturbing the user
    BOOL installationCancelled = (!performedSecondStage && secondStageError.code == SUInstallationCancelledError);
    if (performedSecondStage || installationCancelled) {
        dispatch_async(dispatch_get_main_queue(), ^{
            uint8_t cancelled = (uint8_t)installationCancelled;
            uint8_t targetTerminated = (uint8_t)self.terminationListener.terminated;
            
            uint8_t sendInfo[] = {cancelled, targetTerminated};
            
            NSData *sendData = [NSData dataWithBytes:sendInfo length:sizeof(sendInfo)];
            [self.remotePort sendMessageWithIdentifier:SUInstallationFinishedStage2 data:sendData completion:^(BOOL success) {
                if (!success) {
                    SULog(@"Error sending stage 2 finish");
                }
                
                if (installationCancelled) {
                    cleanupAndExit();
                }
            }];
        });
    }
    
    if (!performedSecondStage && !installationCancelled) {
        cleanupAndExit();
    }
}

- (void)finishInstallationAfterHostTermination
{
    [self.terminationListener startListeningWithCompletion:^{
        // Launch our installer progress UI tool if only after a certain amount of time passes
        __block NSRunningApplication *installerProgressRunningApplication = nil;
        __block BOOL shouldLaunchInstallerProgress = YES;
        
        NSString *progressToolPath = self.installationData.progressToolPath;
        if (progressToolPath != nil && self.shouldShowUI && ![self.installer displaysUserProgress]) {
            NSURL *progressToolURL = [NSURL fileURLWithPath:progressToolPath];
            if (progressToolURL != nil) {
                NSError *quarantineError = nil;
                if (![[SUFileManager defaultManager] releaseItemFromQuarantineAtRootURL:progressToolURL error:&quarantineError]) {
                    SULog(@"Error: Failed releasing quarantine from installer progress tool: %@", quarantineError);
                }
                
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SUDisplayProgressTimeDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    // Make sure we're still eligible for showing the installer progress
                    // Also if the updater process is still alive, showing the progress should not be our duty
                    if (shouldLaunchInstallerProgress && self.remotePort == nil) {
                        NSError *launchError = nil;
                        
                        NSArray *arguments = @[self.host.bundlePath];
                        NSRunningApplication *runningApplication = [[NSWorkspace sharedWorkspace] launchApplicationAtURL:progressToolURL options:(NSWorkspaceLaunchOptions)(NSWorkspaceLaunchDefault | NSWorkspaceLaunchNewInstance) configuration:@{NSWorkspaceLaunchConfigurationArguments : arguments} error:&launchError];
                        
                        if (runningApplication == nil) {
                            SULog(@"Failed to launch installer progress tool with error: %@", launchError);
                        } else {
                            installerProgressRunningApplication = runningApplication;
                        }
                    }
                });
            }
        }
        
        dispatch_async(self.installerQueue, ^{
            [self performStage2InstallationIfNeeded];
            
            if (!self.performedStage2Installation) {
                // We failed and we're going to exit shortly
                return;
            }
            
            NSError *thirdStageError = nil;
            if (![self.installer performThirdStage:&thirdStageError]) {
                SULog(@"Failed to finalize installation with error: %@", thirdStageError);
                
                [self.installer cleanup];
                self.installer = nil;
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self cleanupAndExitWithStatus:EXIT_FAILURE];
                });
                return;
            }
            
            self.performedStage3Installation = YES;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                // Make sure to terminate our displayed progress before we move onto cleanup
                [installerProgressRunningApplication terminate];
                shouldLaunchInstallerProgress = NO;
                
                [self.remotePort sendMessageWithIdentifier:SUInstallationFinishedStage3 data:[NSData data] completion:^(BOOL success) {
                    if (!success) {
                        SULog(@"Error sending stage 3 finish");
                    }
                }];
                
                // Invalidate the local port before re-launching the updated app
                // If we don't do this, the updated app could think the installation can be resumable,
                // if it checks for updates immediately on launch
                [self.localPort invalidate];
                self.localPort = nil;
                
                NSString *installationPath = [SUInstaller installationPathForHost:self.host];
                
                if (self.shouldRelaunch) {
                    NSString *pathToRelaunch = nil;
                    // If the installation path differs from the host path, we give higher precedence for it than
                    // if the desired relaunch path differs from the host path
                    if (![installationPath.pathComponents isEqualToArray:self.host.bundlePath.pathComponents] || [self.installationData.relaunchPath.pathComponents isEqualToArray:self.host.bundlePath.pathComponents]) {
                        pathToRelaunch = installationPath;
                    } else {
                        pathToRelaunch = self.installationData.relaunchPath;
                    }
                    
                    [self relaunchAtPath:pathToRelaunch];
                }
                
                dispatch_async(self.installerQueue, ^{
                    [self.installer cleanup];
                    
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SUTerminationTimeDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                        [self cleanupAndExitWithStatus:EXIT_SUCCESS];
                    });
                });
            });
        });
    }];
}

- (void)cleanupAndExitWithStatus:(int)status __attribute__((noreturn))
{
    // It's nice to tell the other end we're invalidating
    
    [self.localPort invalidate];
    self.localPort = nil;
    
    [self.remotePort invalidate];
    self.remotePort = nil;
    
    NSError *theError = nil;
    if (![[NSFileManager defaultManager] removeItemAtPath:self.installationData.updateDirectoryPath error:&theError]) {
        SULog(@"Couldn't remove update folder: %@.", theError);
    }
    
    [[NSFileManager defaultManager] removeItemAtPath:[[NSBundle mainBundle] bundlePath] error:NULL];
    
    exit(status);
}

- (void)relaunchAtPath:(NSString *)relaunchPath
{
    // Don't use -launchApplication: because we may not be launching an application. Eg: it could be a system prefpane
    if (![[NSWorkspace sharedWorkspace] openFile:relaunchPath]) {
        SULog(@"Failed to launch %@", relaunchPath);
    }
}

@end
