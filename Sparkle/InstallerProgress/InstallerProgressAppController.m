//
//  InstallerProgressAppController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "InstallerProgressAppController.h"
#import "InstallerProgressDelegate.h"
#import "SPUMessageTypes.h"
#import "SULog.h"
#import "SULog+NSError.h"
#import "SUApplicationInfo.h"
#import "SPUInstallerAgentProtocol.h"
#import "SUInstallerAgentInitiationProtocol.h"
#import "StatusInfo.h"
#import "SUHost.h"
#import "SUErrors.h"
#import "SUNormalization.h"
#import "SUConstants.h"
#import "SPUSecureCoding.h"
#import "SPUInstallationInfo.h"

/**
 * Terminate the application after a delay from launching the new update to avoid OS activation issues
 * This delay should be be high enough to increase the likelihood that our updated app will be launched up front,
 * but should be low enough so that the user doesn't ponder why the updater hasn't finished terminating yet
 */
static const NSTimeInterval SUTerminationTimeDelay = 0.3;

@interface InstallerProgressAppController () <NSApplicationDelegate, SPUInstallerAgentProtocol>

@property (nonatomic, readonly) NSApplication *application;
@property (nonatomic, weak) id<InstallerProgressDelegate> delegate;
@property (nonatomic, readonly) NSXPCConnection *connection;
@property (nonatomic) BOOL connected;
@property (nonatomic) BOOL repliedToRegistration;
@property (nonatomic, readonly) SUHost *oldHost;
@property (nonatomic, readonly) BOOL shouldRelaunchHostBundle;
@property (nonatomic, readonly) NSString *oldHostBundlePath;
@property (nonatomic, readonly) BOOL systemDomain;
@property (nonatomic) StatusInfo *statusInfo;
@property (nonatomic) BOOL submittedLauncherJob;
@property (nonatomic) BOOL willTerminate;
@property (nonatomic) BOOL applicationInitiallyAlive;
@property (nonatomic) NSBundle *applicationBundle;
@property (nonatomic) NSString *normalizedPath;

@end

#define CONNECTION_ACKNOWLEDGEMENT_TIMEOUT 7ull

@implementation InstallerProgressAppController

@synthesize application = _application;
@synthesize delegate = _delegate;
@synthesize connection = _connection;
@synthesize connected = _connected;
@synthesize repliedToRegistration = _repliedToRegistration;
@synthesize oldHost = _oldHost;
@synthesize shouldRelaunchHostBundle = _shouldRelaunchHostBundle;
@synthesize oldHostBundlePath = _oldHostBundlePath;
@synthesize systemDomain = _systemDomain;
@synthesize statusInfo = _statusInfo;
@synthesize submittedLauncherJob = _submittedLauncherJob;
@synthesize willTerminate = _willTerminate;
@synthesize applicationInitiallyAlive = _applicationInitiallyAlive;
@synthesize applicationBundle = _applicationBundle;
@synthesize normalizedPath = _normalizedPath;

- (instancetype)initWithApplication:(NSApplication *)application arguments:(NSArray<NSString *> *)arguments delegate:(id<InstallerProgressDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        if (arguments.count != 3) {
            SULog(SULogLevelError, @"Error: Invalid number of arguments supplied: %@", arguments);
            [self cleanupAndExitWithStatus:EXIT_FAILURE error:nil];
        }
        
        NSString *hostBundlePath = arguments[1];
        if (hostBundlePath.length == 0) {
            SULog(SULogLevelError, @"Error: Host bundle path length is 0");
            [self cleanupAndExitWithStatus:EXIT_FAILURE error:nil];
        }
        
        NSBundle *hostBundle = [NSBundle bundleWithPath:hostBundlePath];
        if (hostBundle == nil) {
            SULog(SULogLevelError, @"Error: Host bundle for target is nil");
            [self cleanupAndExitWithStatus:EXIT_FAILURE error:nil];
        }
        
        NSString *hostBundleIdentifier = hostBundle.bundleIdentifier;
        if (hostBundleIdentifier == nil) {
            SULog(SULogLevelError, @"Error: Host bundle identifier for target is nil");
            [self cleanupAndExitWithStatus:EXIT_FAILURE error:nil];
            return nil; // just to silence analyzer warnings later about hostBundleIdentifier being nil
        }
        
        SUHost *host = [[SUHost alloc] initWithBundle:hostBundle];
        _shouldRelaunchHostBundle = [host boolForInfoDictionaryKey:SURelaunchHostBundleKey];
        _oldHostBundlePath = host.bundlePath;
        
        _oldHost = host;
        
        // Note that we are connecting to the installer rather than the installer connecting to us
        // This difference is significant. We shouldn't have a model where the 'server' tries to connect to a 'client',
        // nor have a model where a process that runs at the highest level (the installer can run as root) tries to connect to a user level agent or process
        BOOL systemDomain = arguments[2].boolValue;
        NSXPCConnectionOptions connectionOptions = systemDomain ? NSXPCConnectionPrivileged : 0;
        
        _systemDomain = systemDomain;
        _connection = [[NSXPCConnection alloc] initWithMachServiceName:SPUProgressAgentServiceNameForBundleIdentifier(hostBundleIdentifier) options:connectionOptions];
        
        _statusInfo = [[StatusInfo alloc] initWithHostBundleIdentifier:hostBundleIdentifier];
        
        application.delegate = self;
        
        _application = application;
        _delegate = delegate;
        
        _connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SPUInstallerAgentProtocol)];
        _connection.exportedObject = self;
        
        _connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerAgentInitiationProtocol)];
        
        __weak InstallerProgressAppController *weakSelf = self;
        _connection.interruptionHandler = ^{
            [weakSelf.connection invalidate];
        };
        
        _connection.invalidationHandler = ^{
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallerProgressAppController *strongSelf = weakSelf;
                if (strongSelf != nil) {
                    int exitStatus = (strongSelf.repliedToRegistration ? EXIT_SUCCESS : EXIT_FAILURE);
                    NSError *registrationError;
                    if (!strongSelf.repliedToRegistration) {
                        registrationError = [NSError errorWithDomain:SUSparkleErrorDomain code:SUAgentInvalidationError userInfo:@{ NSLocalizedDescriptionKey: @"Error: Agent Invalidating without having the chance to reply to installer" }];
                    } else {
                        registrationError = nil;
                    }
                    if (!strongSelf.willTerminate) {
                        [strongSelf cleanupAndExitWithStatus:exitStatus error:registrationError];
                    }
                }
            });
        };
    }
    return self;
}

- (void)run
{
    [self.application run];
}

- (void)startConnection
{
    [self.statusInfo startListener];
    
    [self.connection resume];
    [(id<SUInstallerAgentInitiationProtocol>)self.connection.remoteObjectProxy connectionDidInitiateWithReply:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            self.connected = YES;
        });
    }];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(CONNECTION_ACKNOWLEDGEMENT_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.connected) {
            SULog(SULogLevelError, @"Timeout error: failed to receive acknowledgement from installer");
            [self cleanupAndExitWithStatus:EXIT_FAILURE error:nil];
        }
    });
}

- (void)applicationDidFinishLaunching:(NSNotification *)__unused notification
{
    [self startConnection];
}

- (void)cleanupAndExitWithStatus:(int)status error:(NSError * _Nullable)error __attribute__((noreturn))
{
    if (error != nil) {
        SULog(SULogLevelError, @"Agent failed..");
        SULogError(error);
        
        [(id<SUInstallerAgentInitiationProtocol>)self.connection.remoteObjectProxy connectionWillInvalidateWithError:error];
    }
    
    [self.statusInfo invalidate];
    [self.connection invalidate];
    
    // Remove the agent bundle; it is assumed this bundle is in a temporary/cache/support directory
    NSError *theError = nil;
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    
    if (![[NSFileManager defaultManager] removeItemAtPath:bundlePath error:&theError]) {
        SULog(SULogLevelError, @"Couldn't remove agent bundle: %@.", theError);
    } else {
        // There should be nothing else in the parent temporary directory given to us,
        // so let us try to remove it. Note rmdir() will fail if there are unexpectably other
        // items present
        NSString *parentDirectory = bundlePath.stringByDeletingLastPathComponent;
        const char *fileSystemRepresentation = parentDirectory.fileSystemRepresentation;
        if (fileSystemRepresentation != NULL) {
            if (rmdir(fileSystemRepresentation) != 0) {
                SULog(SULogLevelError, @"Failed to remove parent agent bundle directory: %@: %d", parentDirectory, errno);
            }
        }
    }
    
    exit(status);
}

- (NSArray<NSRunningApplication *> *)runningApplicationsWithBundle:(NSBundle *)bundle
{
    // Resolve symlinks otherwise when we compare file paths, we may not realize two paths that are represented differently are the same
    NSArray<NSString *> *bundlePathComponents = bundle.bundlePath.stringByResolvingSymlinksInPath.pathComponents;
    NSString *bundleIdentifier = bundle.bundleIdentifier;
    
    NSMutableArray<NSRunningApplication *> *matchedRunningApplications = [[NSMutableArray alloc] init];
    
    if (bundleIdentifier != nil && bundlePathComponents != nil) {
        NSArray *runningApplications =
        (bundleIdentifier != nil) ?
        [NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier] :
        [[NSWorkspace sharedWorkspace] runningApplications];
        
        for (NSRunningApplication *runningApplication in runningApplications) {
            // Comparing the URLs hasn't worked well for me in practice, so I'm comparing the file paths instead
            NSString *candidatePath = runningApplication.bundleURL.URLByResolvingSymlinksInPath.path;
            if (candidatePath != nil && [candidatePath.pathComponents isEqualToArray:bundlePathComponents]) {
                [matchedRunningApplications addObject:runningApplication];
            }
        }
    }
    
    return [matchedRunningApplications copy];
}

- (void)registerApplicationBundlePath:(NSString *)applicationBundlePath reply:(void (^)(NSNumber *))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (applicationBundlePath != nil && !self.willTerminate) {
            NSBundle *applicationBundle = [NSBundle bundleWithPath:applicationBundlePath];
            if (applicationBundle == nil) {
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SUAgentInvalidationError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Error: Encountered invalid path for waiting termination: %@", applicationBundlePath] }]];
            }
            
            // Compute normalized path that we may use later for relaunching the application
            // We compute normalized path from progress agent instead of trusting or having the installer
            // pass it to us
            if (SPARKLE_NORMALIZE_INSTALLED_APPLICATION_NAME && [applicationBundle.bundlePath isEqualToString:self.oldHostBundlePath]) {
                NSString *normalizedPath = SUNormalizedInstallationPath(self.oldHost);
                // We only use normalized path if it doesn't already exist
                // Check the installer which has the same logic
                if (![[NSFileManager defaultManager] fileExistsAtPath:normalizedPath]) {
                    self.normalizedPath = SUNormalizedInstallationPath(self.oldHost);
                }
            }
            
            NSArray<NSRunningApplication *> *runningApplications = [self runningApplicationsWithBundle:applicationBundle];
            
            // We're just picking the first running application to send..
            // Ideally we'd send them all and have the installer monitor all of them but I don't want to deal with that complexity at the moment
            // Although that would still have the issue if another instance of the application launched during that duration
            // At the same time we don't want the installer to be over-reliant on us (the agent tool) in a way that could leave the installer as a zombie by accident
            // In other words, the installer should be monitoring for dead processes, not us
            // Lastly we don't handle monitoring or terminating processes from logged in users
            NSRunningApplication *firstRunningApplication = runningApplications.firstObject;
            NSNumber *processIdentifier = (firstRunningApplication == nil || firstRunningApplication.terminated) ? nil : @(firstRunningApplication.processIdentifier);
            
            reply(processIdentifier);
            
            self.repliedToRegistration = YES;
            self.applicationBundle = applicationBundle;
            self.applicationInitiallyAlive = (processIdentifier != nil);
        } else {
            assert(false);
        }
    });
}

- (void)registerInstallationInfoData:(NSData *)installationInfoData
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.statusInfo.installationInfoData == nil && installationInfoData != nil) {
            SPUInstallationInfo *installationInfo = (SPUInstallationInfo *)SPUUnarchiveRootObjectSecurely(installationInfoData, [SPUInstallationInfo class]);
            
            if (installationInfo != nil) {
                installationInfo.systemDomain = self.systemDomain;
                self.statusInfo.installationInfoData = SPUArchiveRootObjectSecurely(installationInfo);
            } else {
                SULog(SULogLevelError, @"Error: Failed to decode initial installation info from installer: %@", installationInfoData);
            }
        }
    });
}

- (void)sendTerminationSignal
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.willTerminate && self.applicationBundle != nil) {
            // Note we are sending an Apple quit event, which gives the application or user a chance to delay or cancel the request, which is what we desire
            for (NSRunningApplication *runningApplication in [self runningApplicationsWithBundle:self.applicationBundle]) {
                [runningApplication terminate];
            }
        }
    });
}

- (void)relaunchApplication
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.willTerminate && self.applicationBundle != nil && self.applicationInitiallyAlive) {
            NSString *pathToRelaunch;
            if (self.normalizedPath != nil) {
                pathToRelaunch = self.normalizedPath;
            } else if (self.shouldRelaunchHostBundle) {
                // Use self.oldHostBundlePath because it was computed before self.oldHost could have been removed
                pathToRelaunch = self.oldHostBundlePath;
            } else {
                pathToRelaunch = self.applicationBundle.bundlePath;
            }
            
            // We should at least make sure we're opening a bundle
            NSBundle *relaunchBundle = [NSBundle bundleWithPath:pathToRelaunch];
            if (relaunchBundle == nil) {
                [self cleanupAndExitWithStatus:EXIT_FAILURE error:[NSError errorWithDomain:SUSparkleErrorDomain code:SUAgentInvalidationError userInfo:@{ NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Error: Encountered invalid path to relaunch: %@", pathToRelaunch] }]];
            }
            
            // Note: we can launch application bundles or open plug-in bundles
            if (![[NSWorkspace sharedWorkspace] openFile:pathToRelaunch]) {
                SULog(SULogLevelError, @"Error: Failed to relaunch bundle at %@", pathToRelaunch);
            }
            
            // Delay termination for a little bit to better increase the chance the updated application when relaunched will be the frontmost application
            // This is related to macOS activation issues when terminating a frontmost application happens right before launching another app
            
            self.willTerminate = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SUTerminationTimeDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self cleanupAndExitWithStatus:EXIT_SUCCESS error:nil];
            });
        }
    });
}

- (void)showProgress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!self.willTerminate) {
            // Show app icon in the dock
            ProcessSerialNumber psn = { 0, kCurrentProcess };
            TransformProcessType(&psn, kProcessTransformToForegroundApplication);
            
            // Note: the application icon needs to be set after showing the icon in the dock
            self.application.applicationIconImage = [SUApplicationInfo bestIconForHost:self.oldHost];
            
            // Activate ourselves otherwise we will probably be in the background
            [self.application activateIgnoringOtherApps:YES];
            
            [self.delegate installerProgressShouldDisplayWithHost:self.oldHost];
        }
    });
}

- (void)stopProgress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // Dismiss any UI immediately
        [self.delegate installerProgressShouldStop];
        self.delegate = nil;
        
        // No need to broadcast status service anymore
        // In fact we shouldn't when we decide to relaunch the update
        [self.statusInfo invalidate];
        self.statusInfo = nil;
    });
}

@end
