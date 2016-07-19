//
//  InstallerProgressAppController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "InstallerProgressAppController.h"
#import "InstallerProgressDelegate.h"
#import "SUMessageTypes.h"
#import "SULog.h"
#import "SUApplicationInfo.h"
#import "SUInstallerAgentProtocol.h"
#import "SUInstallerAgentInitiationProtocol.h"
#import "InstallerProgressLauncher.h"
#import "StatusInfo.h"
#import <ServiceManagement/ServiceManagement.h>

/*!
 * Terminate the application after a delay from launching the new update to avoid OS activation issues
 * This delay should be be high enough to increase the likelihood that our updated app will be launched up front,
 * but should be low enough so that the user doesn't ponder why the updater hasn't finished terminating yet
 */
static const NSTimeInterval SUTerminationTimeDelay = 0.3;

@interface InstallerProgressAppController () <NSApplicationDelegate, SUInstallerAgentProtocol, InstallerProgressLauncherDelegate>

@property (nonatomic, readonly) NSApplication *application;
@property (nonatomic, weak) id<InstallerProgressDelegate> delegate;
@property (nonatomic, readonly) NSXPCConnection *connection;
@property (nonatomic) BOOL connected;
@property (nonatomic) BOOL repliedToRegistration;
@property (nonatomic, readonly) NSBundle *hostBundle;
@property (nonatomic, readonly, nullable) InstallerProgressLauncher *progressLauncher;
@property (nonatomic) StatusInfo *statusInfo;
@property (nonatomic) BOOL submittedLauncherJob;

@end

#define CONNECTION_ACKNOWLEDGEMENT_TIMEOUT 7ull

@implementation InstallerProgressAppController

@synthesize application = _application;
@synthesize delegate = _delegate;
@synthesize connection = _connection;
@synthesize connected = _connected;
@synthesize repliedToRegistration = _repliedToRegistration;
@synthesize hostBundle = _hostBundle;
@synthesize progressLauncher = _progressLauncher;
@synthesize statusInfo = _statusInfo;
@synthesize submittedLauncherJob = _submittedLauncherJob;

- (instancetype)initWithApplication:(NSApplication *)application arguments:(NSArray<NSString *> *)arguments delegate:(id<InstallerProgressDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        if (arguments.count != 5) {
            SULog(@"Error: Invalid arguments");
            [self cleanupAndExitWithStatus:EXIT_FAILURE];
        }
        
        NSString *hostBundlePath = arguments[1];
        if (hostBundlePath.length == 0) {
            SULog(@"Error: Host bundle path length is 0");
            [self cleanupAndExitWithStatus:EXIT_FAILURE];
        }
        
        _hostBundle = [NSBundle bundleWithPath:hostBundlePath];
        if (_hostBundle == nil) {
            SULog(@"Error: Host bundle for target is nil");
            [self cleanupAndExitWithStatus:EXIT_FAILURE];
        }
        
        NSString *hostBundleIdentifier = _hostBundle.bundleIdentifier;
        if (hostBundleIdentifier == nil) {
            SULog(@"Error: Host bundle identifier for target is nil");
            [self cleanupAndExitWithStatus:EXIT_FAILURE];
        }
        
        BOOL allowingInteraction = arguments[2].boolValue;
        
        NSString *installerPath = arguments[3];
        if (installerPath.length == 0) {
            SULog(@"Error: Installer path length is 0");
            [self cleanupAndExitWithStatus:EXIT_FAILURE];
        }
        
        BOOL shouldSubmitInstaller = arguments[4].boolValue;
        if (shouldSubmitInstaller) {
            _progressLauncher = [[InstallerProgressLauncher alloc] initWithHostBundle:_hostBundle installerPath:installerPath allowingInteraction:allowingInteraction delegate:self];
        }
        
        _statusInfo = [[StatusInfo alloc] initWithHostBundleIdentifier:hostBundleIdentifier];
        
        application.delegate = self;
        
        _application = application;
        _delegate = delegate;
        
        NSXPCConnectionOptions connectionOptions = shouldSubmitInstaller ? NSXPCConnectionPrivileged : 0;
        _connection = [[NSXPCConnection alloc] initWithMachServiceName:SUProgressAgentServiceNameForBundleIdentifier(hostBundleIdentifier) options:connectionOptions];
        
        _connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUInstallerAgentProtocol)];
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
                    if (!strongSelf.repliedToRegistration) {
                        SULog(@"Error: Agent Invalidating without having the chance to reply to installer");
                    }
                    [strongSelf cleanupAndExitWithStatus:exitStatus];
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
    [self.connection.remoteObjectProxy connectionDidInitiateWithReply:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            self.connected = YES;
        });
    }];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(CONNECTION_ACKNOWLEDGEMENT_TIMEOUT * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (!self.connected) {
            SULog(@"Timeout error: failed to receive acknowledgement from installer");
            [self cleanupAndExitWithStatus:EXIT_FAILURE];
        }
    });
}

- (void)applicationDidFinishLaunching:(NSNotification *)__unused notification
{
    if (self.progressLauncher == nil) {
        [self startConnection];
    } else {
        [self.progressLauncher startListener];
    }
}

- (void)cleanupAndExitWithStatus:(int)status __attribute__((noreturn))
{
    [self.statusInfo invalidate];
    [self.connection invalidate];
    [self.progressLauncher invalidate];
    
    exit(status);
}

- (void)installerProgressLauncherDidSubmitJob
{
    self.submittedLauncherJob = YES;
    [self startConnection];
}

- (void)installerProgressLauncherDidInvalidate
{
    if (!self.submittedLauncherJob) {
        SULog(@"Installer progress launcher invalidated");
        [self cleanupAndExitWithStatus:EXIT_FAILURE];
    }
}

- (void)registerRelaunchBundlePath:(NSString *)relaunchBundlePath reply:(void (^)(NSNumber *))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        assert(relaunchBundlePath != nil);
        NSBundle *relaunchBundle = [NSBundle bundleWithPath:relaunchBundlePath];
        if (relaunchBundle == nil) {
            [self cleanupAndExitWithStatus:EXIT_FAILURE];
        }
        
        NSRunningApplication *runningApplication = [SUApplicationInfo runningApplicationWithBundle:relaunchBundle];
        NSNumber *processIdentifier = (runningApplication == nil || runningApplication.terminated) ? nil : @(runningApplication.processIdentifier);
        
        reply(processIdentifier);
        
        self.repliedToRegistration = YES;
    });
}

- (void)registerInstallationInfoData:(NSData *)installationInfoData
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.statusInfo.installationInfoData == nil) {
            self.statusInfo.installationInfoData = installationInfoData;
        }
    });
}

- (void)relaunchPath:(NSString *)pathToRelaunch
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![[NSWorkspace sharedWorkspace] openFile:pathToRelaunch]) {
            SULog(@"Error: Failed to relaunch bundle at %@", pathToRelaunch);
        }
    });
}

- (void)showProgress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        // Show app icon in the dock
        ProcessSerialNumber psn = { 0, kCurrentProcess };
        TransformProcessType(&psn, kProcessTransformToForegroundApplication);
        
        // Note: the application icon needs to be set after showing the icon in the dock
        self.application.applicationIconImage = [SUApplicationInfo bestIconForBundle:self.hostBundle];
        
        // Activate ourselves otherwise we will probably be in the background
        [self.application activateIgnoringOtherApps:YES];
        
        [self.delegate installerProgressShouldDisplayWithBundle:self.hostBundle];
    });
}

- (void)stopProgress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _stopProgress];
    });
}

- (void)_stopProgress
{
    [self.statusInfo invalidate];
    self.statusInfo = nil;
    
    [self.delegate installerProgressShouldStop];
    self.delegate = nil;
}

// Dismiss any UI immediately, but delay termination for a little bit to better increase the chance
// the updated application when relaunched will be the frontmost application
// This is related to macOS activation issues when terminating a frontmost application happens right before
// launching another app
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)__unused sender
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SUTerminationTimeDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Exit right away, don't go through the apple event process again
        [self cleanupAndExitWithStatus:EXIT_SUCCESS];
    });
    
    [self _stopProgress];
    
    // Reply with a 'cancel' rather than 'later' because 'later' may make the runloop stop completely, not having the dispatch_after above invoked
    return NSTerminateCancel;
}

@end
