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
#import "SPUApplicationInfo.h"
#import "SPUInstallerAgentProtocol.h"
#import "SUInstallerAgentInitiationProtocol.h"
#import "StatusInfo.h"

/*!
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
@property (nonatomic, readonly) NSBundle *hostBundle;
@property (nonatomic) StatusInfo *statusInfo;
@property (nonatomic) BOOL submittedLauncherJob;
@property (nonatomic) BOOL willTerminate;

@end

#define CONNECTION_ACKNOWLEDGEMENT_TIMEOUT 7ull

@implementation InstallerProgressAppController

@synthesize application = _application;
@synthesize delegate = _delegate;
@synthesize connection = _connection;
@synthesize connected = _connected;
@synthesize repliedToRegistration = _repliedToRegistration;
@synthesize hostBundle = _hostBundle;
@synthesize statusInfo = _statusInfo;
@synthesize submittedLauncherJob = _submittedLauncherJob;
@synthesize willTerminate = _willTerminate;

- (instancetype)initWithApplication:(NSApplication *)application arguments:(NSArray<NSString *> *)arguments delegate:(id<InstallerProgressDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        if (arguments.count != 3) {
            SULog(@"Error: Invalid number of arguments supplied: %@", arguments);
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
        
        // Note that we are connecting to the installer rather than the installer connecting to us
        // This difference is significant. We shouldn't have a model where the 'server' tries to connect to a 'client',
        // nor have a model where a process that runs at the highest level (the installer can run as root) tries to connect to a user level agent or process
        BOOL systemDomain = arguments[2].boolValue;
        NSXPCConnectionOptions connectionOptions = systemDomain ? NSXPCConnectionPrivileged : 0;
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
                    if (!strongSelf.repliedToRegistration) {
                        SULog(@"Error: Agent Invalidating without having the chance to reply to installer");
                    }
                    if (!strongSelf.willTerminate) {
                        [strongSelf cleanupAndExitWithStatus:exitStatus];
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
    [self startConnection];
}

- (void)cleanupAndExitWithStatus:(int)status __attribute__((noreturn))
{
    [self.statusInfo invalidate];
    [self.connection invalidate];
    
    // Remove the agent bundle; it is assumed this bundle is in a temporary/cache/support directory
    NSError *theError = nil;
    if (![[NSFileManager defaultManager] removeItemAtPath:[[NSBundle mainBundle] bundlePath] error:&theError]) {
        SULog(@"Couldn't remove agent bundle: %@.", theError);
    }
    
    exit(status);
}

- (void)registerRelaunchBundlePath:(NSString *)relaunchBundlePath reply:(void (^)(NSNumber *))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (relaunchBundlePath != nil && !self.willTerminate) {
            NSBundle *relaunchBundle = [NSBundle bundleWithPath:relaunchBundlePath];
            if (relaunchBundle == nil) {
                [self cleanupAndExitWithStatus:EXIT_FAILURE];
            }
            
            NSRunningApplication *runningApplication = [SPUApplicationInfo runningApplicationWithBundle:relaunchBundle];
            NSNumber *processIdentifier = (runningApplication == nil || runningApplication.terminated) ? nil : @(runningApplication.processIdentifier);
            
            reply(processIdentifier);
            
            self.repliedToRegistration = YES;
        }
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
        if (!self.willTerminate) {
            // We only launch applications, but I'm not sure how reliable -launchApplicationAtURL:options:config: is so we're not using it
            // Eg: http://www.openradar.me/10952677
            if (![[NSWorkspace sharedWorkspace] openFile:pathToRelaunch]) {
                SULog(@"Error: Failed to relaunch bundle at %@", pathToRelaunch);
            }
            
            // Delay termination for a little bit to better increase the chance the updated application when relaunched will be the frontmost application
            // This is related to macOS activation issues when terminating a frontmost application happens right before launching another app
            
            self.willTerminate = YES;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SUTerminationTimeDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self cleanupAndExitWithStatus:EXIT_SUCCESS];
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
            self.application.applicationIconImage = [SPUApplicationInfo bestIconForBundle:self.hostBundle];
            
            // Activate ourselves otherwise we will probably be in the background
            [self.application activateIgnoringOtherApps:YES];
            
            [self.delegate installerProgressShouldDisplayWithBundle:self.hostBundle];
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
