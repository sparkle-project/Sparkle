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
#import "SULocalMessagePort.h"
#import "SURemoteMessagePort.h"
#import "SUUpdaterDelegate.h"
#import "SUAppcastItem.h"
#import "SULog.h"
#import "SULocalizations.h"
#import "SUErrors.h"
#import "SUHost.h"
#import "SUFileManager.h"
#import "SUSecureCoding.h"
#import "SUInstallationInputData.h"
#import "SUInstallerLauncherProtocol.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUInstallerDriver ()

@property (nonatomic, readonly) SUHost *host;
@property (nonatomic, readonly, copy) NSString *cachePath;
@property (nonatomic, readonly) NSBundle *sparkleBundle;
@property (nonatomic, weak, readonly) id<SUInstallerDriverDelegate> delegate;
@property (nonatomic) SUInstallerMessageType currentStage;
@property (nonatomic) SULocalMessagePort *localPort;
@property (nonatomic) SURemoteMessagePort *remotePort;
@property (nonatomic) BOOL postponedOnce;
@property (nonatomic, weak, readonly) id updater;
@property (nonatomic, weak, readonly) id<SUUpdaterDelegate> updaterDelegate;

@property (nonatomic) SUAppcastItem *updateItem;
@property (nonatomic, copy) NSString *downloadPath;
@property (nonatomic, copy) NSString *temporaryDirectory;

@end

@implementation SUInstallerDriver

@synthesize host = _host;
@synthesize cachePath = _cachePath;
@synthesize sparkleBundle = _sparkleBundle;
@synthesize delegate = _delegate;
@synthesize currentStage = _currentStage;
@synthesize localPort = _localPort;
@synthesize remotePort = _remotePort;
@synthesize postponedOnce = _postponedOnce;
@synthesize updater = _updater;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize updateItem = _updateItem;
@synthesize downloadPath = _downloadPath;
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

- (BOOL)setUpLocalPort:(NSError * __autoreleasing *)error
{
    if (self.localPort != nil) {
        return YES;
    }
    
    NSString *hostBundleIdentifier = self.host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    
    self.localPort =
    [[SULocalMessagePort alloc]
     initWithServiceName:SUUpdateDriverServiceNameForBundleIdentifier(hostBundleIdentifier)
     messageCallback:^NSData *(int32_t identifier, NSData * _Nonnull data) {
         dispatch_async(dispatch_get_main_queue(), ^{
             [self handleMessageWithIdentifier:identifier data:data];
         });
         return nil;
     }
     invalidationCallback:^{
         dispatch_async(dispatch_get_main_queue(), ^{
             if (self.localPort != nil) {
                 NSError *invalidationError =
                 [NSError
                  errorWithDomain:SUSparkleErrorDomain
                  code:SUInstallationError
                  userInfo:@{
                             NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while running the updater. Please try again later.", nil),
                             NSLocalizedFailureReasonErrorKey:@"The local port connection from the updater was invalidated"
                             }
                  ];
                 
                 [self.delegate installerIsRequestingAbortInstallWithError:invalidationError];
             }
         });
     }];
    
    if (self.localPort == nil) {
        if (error != NULL) {
            *error =
            [NSError
             errorWithDomain:SUSparkleErrorDomain
             code:SUInstallationError
             userInfo:@{
                        NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while running the updater. Please try again later.", nil),
                        NSLocalizedFailureReasonErrorKey:@"The local port connection failed being created"
                        }
             ];
        }
        return NO;
    }
    return YES;
}

- (BOOL)setUpRemotePort:(NSError * __autoreleasing *)error
{
    if (self.remotePort != nil) {
        return YES;
    }
    
    NSString *hostBundleIdentifier = self.host.bundle.bundleIdentifier;
    assert(hostBundleIdentifier != nil);
    
    self.remotePort = [[SURemoteMessagePort alloc] initWithServiceName:SUAutoUpdateServiceNameForBundleIdentifier(hostBundleIdentifier) invalidationCallback:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.remotePort != nil) {
                NSError *remoteError =
                [NSError
                 errorWithDomain:SUSparkleErrorDomain
                 code:SUInstallationError
                 userInfo:@{
                            NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while running the updater. Please try again later.", nil),
                            NSLocalizedFailureReasonErrorKey:@"The remote port connection was invalidated from the updater"
                            }
                 ];
                [self.delegate installerIsRequestingAbortInstallWithError:remoteError];
            }
        });
    }];
    
    if (self.remotePort == nil) {
        NSError *remoteError =
        [NSError
         errorWithDomain:SUSparkleErrorDomain
         code:SUInstallationError
         userInfo:@{
                    NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while running the updater. Please try again later.", nil),
                    NSLocalizedFailureReasonErrorKey:@"The remote port connection failed being created"
                    }
         ];
        
        if (error != NULL) {
            *error = remoteError;
        }
        
        return NO;
    }
    return YES;
}

- (void)launchInstallToolWithCompletion:(void (^)(NSError  * _Nullable ))completionHandler
{
    NSError *localPortError = nil;
    if (![self setUpLocalPort:&localPortError]) {
        completionHandler(localPortError);
    }
    
    [self launchAutoUpdateWithCompletion:completionHandler];
}

// This can be called multiple times (eg: if a delta update fails, this may be called again with a regular update item)
- (void)extractDownloadPath:(NSString *)downloadPath withUpdateItem:(SUAppcastItem *)updateItem temporaryDirectory:(NSString *)temporaryDirectory completion:(void (^)(NSError * _Nullable))completionHandler
{
    self.updateItem = updateItem;
    self.temporaryDirectory = temporaryDirectory;
    self.downloadPath = downloadPath;
    
    self.currentStage = SUInstallerNotStarted;
    
    if (self.localPort == nil) {
        [self launchInstallToolWithCompletion:completionHandler];
    } else {
        // The Install tool is already alive; just send out installation input data again
        [self sendInstallationData];
        completionHandler(nil);
    }
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
    
    SUInstallationInputData *installationData = [[SUInstallationInputData alloc] initWithRelaunchPath:pathToRelaunch hostBundlePath:self.host.bundlePath updateDirectoryPath:self.temporaryDirectory downloadPath:self.downloadPath dsaSignature:dsaSignature decryptionPassword:decryptionPassword];
    
    NSData *archivedData = SUArchiveRootObjectSecurely(installationData);
    
    NSError *remoteError = nil;
    if (![self setUpRemotePort:&remoteError]) {
        [self.delegate installerIsRequestingAbortInstallWithError:remoteError];
    } else {
        [self.remotePort sendMessageWithIdentifier:SUInstallationData data:archivedData completion:^(BOOL success) {
            if (!success) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate installerIsRequestingAbortInstallWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey:SULocalizedString(@"An error occurred while starting the installer parameters. Please try again later.", nil) }]];
                });
            }
        }];
        
        self.currentStage = SURequestInstallationParameters;
    }
}

- (void)handleMessageWithIdentifier:(int32_t)identifier data:(NSData *)data
{
    if (!SUInstallerMessageTypeIsLegal(self.currentStage, identifier)) {
        SULog(@"Error: received out of order message with current stage: %d, requested stage: %d", self.currentStage, identifier);
        return;
    }
    
    if (identifier == SURequestInstallationParameters) {
        [self sendInstallationData];
    } else if (identifier == SUExtractedArchiveWithProgress) {
        if (data.length == sizeof(double)) {
            double progress = *(const double *)data.bytes;
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
        
    } else if (identifier == SUInstallationFinishedStage1) {
        self.currentStage = identifier;
        
        // Let the installer keep a copy of the appcast item data
        // We may want to ask for it later (note the updater can relaunch without the app necessarily having relaunched)
        NSData *updateItemData = SUArchiveRootObjectSecurely(self.updateItem);
        
        if (updateItemData != nil) {
            [self.remotePort sendMessageWithIdentifier:SUSentUpdateAppcastItemData data:updateItemData completion:^(BOOL success) {
                if (!success) {
                    SULog(@"Error: Failed to send update appcast item to installer");
                }
            }];
        } else {
            SULog(@"Error: Archived data to send for appcast item is nil");
        }
        
        [self.delegate installerDidFinishRelaunchPreparation];
    } else if (identifier == SUInstallationFinishedStage2) {
        // Don't have to store current stage because we're severing our connection to the installer
        
        [self.remotePort invalidate];
        self.remotePort = nil;
        
        [self.localPort invalidate];
        self.localPort = nil;
        
        [self.delegate installerIsRequestingAppTermination];
    }
}

// Creates intermediate directories up until targetPath if they don't already exist,
// and removes the directory at targetPath if one already exists there
- (BOOL)preparePathForRelaunchTool:(NSString *)targetPath error:(NSError * __autoreleasing *)error
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

- (void)launchAutoUpdateWithCompletion:(void (^)(NSError *_Nullable))completionHandler
{
    NSBundle *sparkleBundle = self.sparkleBundle;
    
    NSString *relaunchPath = nil;
    
    // Copy the relauncher into a temporary directory so we can get to it after the new version's installed.
    // Only the paranoid survive: if there's already a stray copy of relaunch there, we would have problems.
    NSString *const relaunchToolName = @"" SPARKLE_RELAUNCH_TOOL_NAME;
    NSString *const relaunchPathToCopy = [sparkleBundle pathForResource:relaunchToolName ofType:@"app"];
    if (relaunchPathToCopy != nil) {
        NSString *targetPath = [self.cachePath stringByAppendingPathComponent:[relaunchPathToCopy lastPathComponent]];
        
        SUFileManager *fileManager = [SUFileManager fileManagerAllowingAuthorization:NO];
        NSError *error = nil;
        
        NSURL *relaunchURLToCopy = [NSURL fileURLWithPath:relaunchPathToCopy];
        NSURL *targetURL = [NSURL fileURLWithPath:targetPath];
        
        // We only need to run our copy of the app by spawning a task
        // Since we are copying the app to a directory that is write-accessible, we don't need to muck with owner/group IDs
        if ([self preparePathForRelaunchTool:targetPath error:&error] && [fileManager copyItemAtURL:relaunchURLToCopy toURL:targetURL error:&error]) {
            relaunchPath = targetPath;
        } else {
            NSError *prepareError =
            [NSError
             errorWithDomain:SUSparkleErrorDomain
             code:SURelaunchError
             userInfo:@{
                        NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while extracting the archive. Please try again later.", nil),
                        NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't copy relauncher (%@) to temporary path (%@)! %@", relaunchPathToCopy, targetPath, (error ? [error localizedDescription] : @"")]
                        }
             ];
            
            completionHandler(prepareError);
            return;
        }
    }
    
    NSString *relaunchToolPath = [[NSBundle bundleWithPath:relaunchPath] bundlePath];
    if (!relaunchToolPath || ![[NSFileManager defaultManager] fileExistsAtPath:relaunchPath]) {
        // Note that we explicitly use the host app's name here, since updating plugin for Mail relaunches Mail, not just the plugin.
        NSError *error =
        [NSError
         errorWithDomain:SUSparkleErrorDomain
         code:SURelaunchError
         userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:SULocalizedString(@"An error occurred while relaunching %1$@, but the new version will be available next time you run %1$@.", nil), [self.host name]],
                    NSLocalizedFailureReasonErrorKey: [NSString stringWithFormat:@"Couldn't find the relauncher (expected to find it at %@)", relaunchPath]
                    }
         ];
        
        // We intentionally don't abandon the update here so that the host won't initiate another.
        completionHandler(error);
        return;
    }
    
    NSString *hostBundleIdentifier = self.host.bundle.bundleIdentifier;
    if (hostBundleIdentifier == nil) {
        NSError *error =
        [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey:SULocalizedString(@"An error occurred while finding the application's bundle identifier. Please try again later.", nil) }];
        
        completionHandler(error);
        return;
    }
    
    NSXPCConnection *launcherConnection = [[NSXPCConnection alloc] initWithServiceName:@"org.sparkle-project.InstallerLauncher"];
    launcherConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerLauncherProtocol)];
    [launcherConnection resume];
    
    __block BOOL retrievedLaunchStatus = NO;
    
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
    
    [launcherConnection.remoteObjectProxy launchInstallerAtPath:relaunchToolPath withArguments:@[hostBundleIdentifier] completion:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            retrievedLaunchStatus = YES;
            [launcherConnection invalidate];
            
            if (!success) {
                NSError *error =
                [NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey:SULocalizedString(@"An error occurred while launching the installer. Please try again later.", nil) }];
                
                completionHandler(error);
            } else {
                completionHandler(nil);
            }
        });
    }];
}

- (BOOL)mayUpdateAndRestart
{
    return (!self.updaterDelegate || ![self.updaterDelegate respondsToSelector:@selector(updaterShouldRelaunchApplication:)] || [self.updaterDelegate updaterShouldRelaunchApplication:self.updater]);
}

- (void)installWithToolAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI
{
#warning this assertion no longer holds trues due to resumability - matters for commented invocation code below
    //assert(self.updateItem);
    
    if (![self mayUpdateAndRestart])
    {
        [self.delegate installerIsRequestingAbortInstallWithError:nil];
        return;
    }
    
    // Give the host app an opportunity to postpone the install and relaunch.
    if (!self.postponedOnce && [self.updaterDelegate respondsToSelector:@selector(updater:shouldPostponeRelaunchForUpdate:untilInvoking:)])
    {
        //        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:@selector(installWithToolAndRelaunch:)]];
        //        [invocation setSelector:@selector(installWithToolAndRelaunch:)];
        //        [invocation setArgument:&relaunch atIndex:2];
        //        [invocation setTarget:self];
        //        self.postponedOnce = YES;
        //        if ([self.updaterDelegate updater:self.updater shouldPostponeRelaunchForUpdate:self.updateItem untilInvoking:invocation]) {
        //            return;
        //        }
    }
    
    // Set up local and remote ports to the installer if they are not set up already
    
    NSError *localPortError = nil;
    if (![self setUpLocalPort:&localPortError]) {
        [self.delegate installerIsRequestingAbortInstallWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey:SULocalizedString(@"An error occurred while starting the local port for the installer. Please try again later.", nil) }]];
        return;
    }
    
    NSError *remotePortError = nil;
    if (![self setUpRemotePort:&remotePortError]) {
        [self.delegate installerIsRequestingAbortInstallWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUInstallationError userInfo:@{ NSLocalizedDescriptionKey:SULocalizedString(@"An error occurred while starting the remote port for the installer. Please try again later.", nil) }]];
        return;
    }
    
    // For resumability, we'll assume we are far enough for the installation to continue
    self.currentStage = SUInstallationFinishedStage1;
    
    uint8_t response[2] = {(uint8_t)relaunch, (uint8_t)showUI};
    NSData *responseData = [NSData dataWithBytes:response length:sizeof(response)];
    
    [self.remotePort sendMessageWithIdentifier:SUResumeInstallationToStage2 data:responseData completion:^(BOOL success) {
        if (!success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *remoteError =
                [NSError
                 errorWithDomain:SUSparkleErrorDomain
                 code:SUInstallationError
                 userInfo:@{
                            NSLocalizedDescriptionKey: SULocalizedString(@"An error occurred while running the updater. Please try again later.", nil),
                            NSLocalizedFailureReasonErrorKey:@"The remote port connection failed to send resume install message"
                            }
                 ];
                [self.delegate installerIsRequestingAbortInstallWithError:remoteError];
            });
        }
        // otherwise we'll terminate later when the installer tells us stage 2 is done
    }];
}

- (void)abortInstall
{
    if (self.localPort != nil) {
        [self.localPort invalidate];
        self.localPort = nil;
    }
    
    if (self.remotePort != nil) {
        [self.remotePort invalidate];
        self.remotePort = nil;
    }
}

@end
