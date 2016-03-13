//
//  AppInstaller.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/7/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "AppInstaller.h"
#import "SUStatusController.h"
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

/*!
 * Terminate the application after a delay from launching the new update to avoid OS activation issues
 * This delay should be be high enough to increase the likelihood that our updated app will be launched up front,
 * but should be low enough so that the user doesn't ponder why the updater hasn't finished terminating yet
 */
static const NSTimeInterval SUTerminationTimeDelay = 0.5;

@interface AppInstaller ()

@property (nonatomic, strong) TerminationListener *terminationListener;
@property (nonatomic, strong) SUStatusController *statusController;

@property (nonatomic) SUHost *host;
@property (nonatomic) SULocalMessagePort *localPort;
@property (nonatomic) SURemoteMessagePort *remotePort;
@property (nonatomic, copy) NSString *updateFolderPath;
@property (nonatomic, copy) NSString *downloadPath;
@property (nonatomic, copy) NSString *dsaSignature;
@property (nonatomic, copy) NSString *relaunchPath;
@property (nonatomic, assign) BOOL shouldRelaunch;
@property (nonatomic, assign) BOOL shouldShowUI;

@property (nonatomic, assign) BOOL isTerminating;
@property (nonatomic) id<SUInstaller> installer;
@property (nonatomic) BOOL willCompleteInstallation;

@property (nonatomic) dispatch_queue_t installerQueue;
@property (nonatomic) BOOL performedStage2Installation;
@property (nonatomic) BOOL handledResumeInstallationToStage2;

@end

@implementation AppInstaller

@synthesize terminationListener = _terminationListener;
@synthesize statusController = _statusController;
@synthesize localPort = _localPort;
@synthesize remotePort = _remotePort;
@synthesize host = _host;
@synthesize updateFolderPath = _updateFolderPath;
@synthesize downloadPath = _downloadPath;
@synthesize dsaSignature = _dsaSignature;
@synthesize relaunchPath = _relaunchPath;
@synthesize shouldRelaunch = _shouldRelaunch;
@synthesize shouldShowUI = _shouldShowUI;
@synthesize isTerminating = _isTerminating;
@synthesize installer = _installer;
@synthesize willCompleteInstallation = _willCompleteInstallation;
@synthesize installerQueue = _installerQueue;
@synthesize performedStage2Installation = _performedStage2Installation;
@synthesize handledResumeInstallationToStage2 = _handledResumeInstallationToStage2;

/*
 * hostPath - path to host (original) application
 * relaunchPath - path to what the host wants to relaunch (default is same as hostPath)
 * hostProcessIdentifier - process identifier of the host before launching us
 * updateFolderPath - path to update folder (i.e, temporary directory containing the new update archive)
 * downloadPath - path to new downloaded update archive
 * shouldRelaunch - indicates if the new installed app should re-launched
 * shouldShowUI - indicates if we should show the status window when installing the update
 */
- (instancetype)initWithHostPath:(NSString *)hostPath relaunchPath:(NSString *)relaunchPath updateFolderPath:(NSString *)updateFolderPath downloadPath:(NSString *)downloadPath dsaSignature:(NSString *)dsaSignature
{
    if (!(self = [super init])) {
        return nil;
    }
    
    NSBundle *bundle = [NSBundle bundleWithPath:hostPath];
    self.host = [[SUHost alloc] initWithBundle:bundle];
    
    self.relaunchPath = relaunchPath;
    self.terminationListener = [[TerminationListener alloc] initWithBundle:bundle];
    self.updateFolderPath = updateFolderPath;
    self.downloadPath = downloadPath;
    self.dsaSignature = dsaSignature;
    
    self.localPort =
    [[SULocalMessagePort alloc]
     initWithServiceName:SUAutoUpdateServiceNameForHost(self.host)
     messageCallback:^(int32_t identifier, NSData * _Nonnull data) {
         dispatch_async(dispatch_get_main_queue(), ^{
             [self handleMessageWithIdentifier:identifier data:data];
         });
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
    } else {
        self.remotePort = [[SURemoteMessagePort alloc] initWithServiceName:SUUpdateDriverServiceNameForHost(self.host) invalidationCallback:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.remotePort != nil && !self.willCompleteInstallation) {
                    SULog(@"Invalidation on remote port being called");
                    [self cleanupAndExitWithStatus:EXIT_FAILURE];
                }
            });
        }];
        
        if (self.remotePort == nil) {
            SULog(@"Failed creating remote message port from installer");
            [self cleanupAndExitWithStatus:EXIT_FAILURE];
        }
    }
    
    return self;
}

/**
 * If the update is a package, then it must be signed using DSA. No other verification is done.
 *
 * If the update is a bundle, then it must meet any one of:
 *
 *  * old and new DSA public keys are the same and valid (it allows change of Code Signing identity), or
 *
 *  * old and new Code Signing identity are the same and valid
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
    
    BOOL dsaKeysMatch = (publicDSAKey == nil || newPublicDSAKey == nil) ? NO : [publicDSAKey isEqualToString:newPublicDSAKey];
    
    if (newPublicDSAKey != nil) {
        if (![SUDSAVerifier validatePath:downloadedPath withEncodedDSASignature:DSASignature withPublicDSAKey:newPublicDSAKey]) {
            SULog(@"DSA signature validation failed. The update has a public DSA key and is signed with a DSA key, but the %@ doesn't match the signature. The update will be rejected.",
                  dsaKeysMatch ? @"public key" : @"new public key shipped with the update");
            return NO;
        }
    }
    
    BOOL updateIsCodeSigned = [SUCodeSigningVerifier applicationAtPathIsCodeSigned:installSourcePath];
    
    if (dsaKeysMatch) {
        NSError *error = nil;
        if (updateIsCodeSigned && ![SUCodeSigningVerifier codeSignatureIsValidAtPath:installSourcePath error:&error]) {
            SULog(@"The update archive has a valid DSA signature, but the app is also signed with Code Signing, which is corrupted: %@. The update will be rejected.", error);
            return NO;
        }
    } else {
        NSString *hostBundlePath = host.bundlePath;
        BOOL hostIsCodeSigned = [SUCodeSigningVerifier applicationAtPathIsCodeSigned:hostBundlePath];
        
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

- (void)extractAndInstallUpdate
{
#warning passing nothing for password atm
    SUUnarchiver *unarchiver = [SUUnarchiver unarchiverForPath:self.downloadPath updatingHostBundlePath:self.host.bundlePath withPassword:nil];
    
    if (!unarchiver) {
        SULog(@"Error: No valid unarchiver for %@!", self.downloadPath);
        [self unarchiverDidFail:nil];
    } else {
        unarchiver.delegate = self;
        [unarchiver start];
    }
}

- (void)unarchiver:(SUUnarchiver *)__unused unarchiver extractedProgress:(double)progress
{
    NSData *data = [NSData dataWithBytes:&progress length:sizeof(progress)];
    [self.remotePort sendMessageWithIdentifier:SUExtractedArchiveWithProgress data:data completion:^(BOOL success) {
        if (!success) {
            SULog(@"Error sending extracted progress");
        }
    }];
}

- (void)unarchiverDidFail:(SUUnarchiver *)__unused unarchiver
{
    [self.remotePort sendMessageWithIdentifier:SUArchiveExtractionFailed data:[NSData data] completion:^(BOOL success) {
        if (!success) {
            SULog(@"Error sending extraction failed");
        }
    }];
}

- (void)unarchiverDidFinish:(SUUnarchiver *)__unused unarchiver
{
    [self.remotePort sendMessageWithIdentifier:SUValidationStarted data:[NSData data] completion:^(BOOL success) {
        if (!success) {
            SULog(@"Error sending validation finish");
        }
    }];
    
    BOOL validationSuccess = [self validateUpdateForHost:self.host downloadedToPath:self.downloadPath extractedToPath:self.updateFolderPath DSASignature:self.dsaSignature];
    
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

- (void)handleMessageWithIdentifier:(int32_t)identifier data:(NSData *)data
{
    if (self.handledResumeInstallationToStage2) {
        return;
    }
    
    if (identifier == SUResumeInstallationToStage2 && data.length == sizeof(uint8_t) * 2) {
        uint8_t relaunch = *((const uint8_t *)data.bytes);
        uint8_t showsUI = *((const uint8_t *)data.bytes + 1);
        
        // By default, if we never get a response from the updater to resume to installation 2,
        // (meaning not getting to this code right here), we do not relaunch or prompt the user for any sort of UI
        self.shouldRelaunch = (BOOL)relaunch;
        self.shouldShowUI = (BOOL)showsUI;
        
        [self resumeInstallation];
        
        self.handledResumeInstallationToStage2 = YES;
    }
}

- (void)startInstallation
{
    self.willCompleteInstallation = YES;
    
    self.installerQueue = dispatch_queue_create("org.sparkle-project.sparkle.installer", DISPATCH_QUEUE_SERIAL);
    
    dispatch_async(self.installerQueue, ^{
        NSError *installerError = nil;
        id <SUInstaller> installer = [SUInstaller installerForHost:self.host updateDirectory:self.updateFolderPath versionComparator:[SUStandardVersionComparator defaultComparator] error:&installerError];
        
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
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.installer = installer;
            
            [self.remotePort sendMessageWithIdentifier:SUInstallationFinishedStage1 data:[NSData data] completion:^(BOOL success) {
                if (!success) {
                    SULog(@"Error sending stage 1 finish");
                }
            }];
            
            [self finishInstallationAfterHostTermination];
        });
    });
}

- (void)performStage2InstallationIfNeeded
{
    if (self.performedStage2Installation) {
        return;
    }
    
    if (self.shouldShowUI) {
        // Predict if an admin prompt is needed
        // If it is, we should activate our app so that the auth prompt will be active
        // (Note it's more efficient/simpler to predict rather than trying, seeing if we fail, notifying, and re-trying)
        NSString *installationPath = self.host.installationPath;
        if (![[NSFileManager defaultManager] isWritableFileAtPath:installationPath]) {
            [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
        }
    }
    
    NSError *secondStageError = nil;
    if (![self.installer performSecondStageAllowingUI:self.shouldShowUI error:&secondStageError]) {
        SULog(@"Error: Failed to resume installer on stage 2 with error: %@", secondStageError);
        [self.installer cleanup];
        self.installer = nil;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self cleanupAndExitWithStatus:EXIT_FAILURE];
        });
        return;
    }
    
    self.performedStage2Installation = YES;
}

- (void)resumeInstallation
{
    dispatch_async(self.installerQueue, ^{
        [self performStage2InstallationIfNeeded];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.remotePort sendMessageWithIdentifier:SUInstallationFinishedStage2 data:[NSData data] completion:^(BOOL success) {
                if (!success) {
                    SULog(@"Error sending stage 2 finish");
                }
            }];
            
            // Stage 3 will perform when the target terminates
        });
    });
}

- (void)finishInstallationAfterHostTermination
{
    [self.terminationListener startListeningWithCompletion:^(BOOL success) {
        self.terminationListener = nil;
        
        if (!success) {
            SULog(@"Timed out waiting for target to terminate. Target path is %@", self.host.bundlePath);
            [self.installer cleanup];
            self.installer = nil;
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self cleanupAndExitWithStatus:EXIT_FAILURE];
            });
            return;
        }
        
        dispatch_async(self.installerQueue, ^{
            [self performStage2InstallationIfNeeded];
            
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
            
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *installationPath = [self.host.installationPath copy];
                
                if (self.shouldRelaunch) {
                    NSString *pathToRelaunch = nil;
                    // If the installation path differs from the host path, we give higher precedence for it than
                    // if the desired relaunch path differs from the host path
                    if (![installationPath.pathComponents isEqualToArray:self.host.bundlePath.pathComponents] || [self.relaunchPath.pathComponents isEqualToArray:self.host.bundlePath.pathComponents]) {
                        pathToRelaunch = installationPath;
                    } else {
                        pathToRelaunch = self.relaunchPath;
                    }
                    
                    [self relaunchAtPath:pathToRelaunch];
                }
                
                dispatch_async(self.installerQueue, ^{
                    [self.installer cleanup];
                    
                    [SUInstaller mdimportInstallationPath:installationPath];
                    
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
    if (![[NSFileManager defaultManager] removeItemAtPath:self.updateFolderPath error:&theError]) {
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
