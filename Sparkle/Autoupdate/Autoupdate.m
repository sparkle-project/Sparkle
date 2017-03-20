#import <Cocoa/Cocoa.h>
#import "SULocalizations.h"
#import "SUErrors.h"
#import "SUInstaller.h"
#import "SUHost.h"
#import "SUStandardVersionComparator.h"
#import "SUStatusController.h"
#import "SULog.h"
#import "SUInstallerProtocol.h"
#import "TerminationListener.h"

#include <unistd.h>

/*!
 * If the Installation takes longer than this time the Application Icon is shown in the Dock so that the user has some feedback.
 */
static const NSTimeInterval SUInstallationTimeLimit = 5;

/*!
 * Terminate the application after a delay from launching the new update to avoid OS activation issues
 * This delay should be be high enough to increase the likelihood that our updated app will be launched up front,
 * but should be low enough so that the user doesn't ponder why the updater hasn't finished terminating yet
 */
static const NSTimeInterval SUTerminationTimeDelay = 0.5;

@interface AppInstaller : NSObject <NSApplicationDelegate>

/*
 * hostPath - path to host (original) application
 * relaunchPath - path to what the host wants to relaunch (default is same as hostPath)
 * parentProcessId - process identifier of the host before launching us
 * updateFolderPath - path to update folder (i.e, temporary directory containing the new update)
 * shouldRelaunch - indicates if the new installed app should re-launched
 * shouldShowUI - indicates if we should show the status window when installing the update
 */
- (instancetype)initWithHostPath:(NSString *)hostPath relaunchPath:(NSString *)relaunchPath parentProcessId:(pid_t)parentProcessId updateFolderPath:(NSString *)updateFolderPath shouldRelaunch:(BOOL)shouldRelaunch shouldShowUI:(BOOL)shouldShowUI;

@end

@interface AppInstaller ()

@property (nonatomic, strong) TerminationListener *terminationListener;
@property (nonatomic, strong) SUStatusController *statusController;

@property (nonatomic, copy) NSString *updateFolderPath;
@property (nonatomic, copy) NSString *hostPath;
@property (nonatomic, copy) NSString *relaunchPath;
@property (nonatomic, assign) BOOL shouldRelaunch;
@property (nonatomic, assign) BOOL shouldShowUI;

@property (nonatomic, assign) BOOL isTerminating;

@end

@implementation AppInstaller

@synthesize terminationListener = _terminationListener;
@synthesize statusController = _statusController;
@synthesize updateFolderPath = _updateFolderPath;
@synthesize hostPath = _hostPath;
@synthesize relaunchPath = _relaunchPath;
@synthesize shouldRelaunch = _shouldRelaunch;
@synthesize shouldShowUI = _shouldShowUI;
@synthesize isTerminating = _isTerminating;

- (instancetype)initWithHostPath:(NSString *)hostPath relaunchPath:(NSString *)relaunchPath parentProcessId:(pid_t)parentProcessId updateFolderPath:(NSString *)updateFolderPath shouldRelaunch:(BOOL)shouldRelaunch shouldShowUI:(BOOL)shouldShowUI
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self.hostPath = hostPath;
    self.relaunchPath = relaunchPath;
    SULog(SULogLevelDefault, @"PID to listen: %d", parentProcessId);
    self.terminationListener = [[TerminationListener alloc] initWithProcessIdentifier:@(parentProcessId)];
    self.updateFolderPath = updateFolderPath;
    self.shouldRelaunch = shouldRelaunch;
    self.shouldShowUI = shouldShowUI;
    
    return self;
}

- (void)applicationDidFinishLaunching:(NSNotification __unused *)notification
{
    [self.terminationListener startListeningWithCompletion:^(BOOL terminationSuccess) {
        self.terminationListener = nil;
        
        if (!terminationSuccess) {
            SULog(SULogLevelError, @"Failed to listen for application termination");
            // Continue on with the installation anyway?
        }
		
        if (self.shouldShowUI) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SUInstallationTimeLimit * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				if (!self.isTerminating) {
					// Show app icon in the dock
					ProcessSerialNumber psn = { 0, kCurrentProcess };
					TransformProcessType(&psn, kProcessTransformToForegroundApplication);
				}
            });
        }
        
        [self install];
    }];
}

- (void)showError:(NSError *)error
{
    if (self.shouldShowUI) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"";
        alert.informativeText = [NSString stringWithFormat:@"%@", [error localizedDescription]];
        [alert runModal];
    }
}

- (void)install
{
    NSBundle *theBundle = [NSBundle bundleWithPath:self.hostPath];
    SUHost *host = [[SUHost alloc] initWithBundle:theBundle];
    
    NSString *fileOperationToolPath = [[[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent] stringByAppendingPathComponent:@""SPARKLE_FILEOP_TOOL_NAME];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:fileOperationToolPath]) {
        SULog(SULogLevelError, @"Potential Installation Error: File operation tool path %@ is not found", fileOperationToolPath);
    }
    
    NSError *retrieveInstallerError = nil;
    id<SUInstallerProtocol> installer = [SUInstaller installerForHost:host fileOperationToolPath:fileOperationToolPath updateDirectory:self.updateFolderPath error:&retrieveInstallerError];
    if (installer == nil) {
        SULog(SULogLevelError, @"Retrieved Installer Error: %@", retrieveInstallerError);
        exit(EXIT_FAILURE);
    }
    
    if (self.shouldShowUI && [installer canInstallSilently]) {
        self.statusController = [[SUStatusController alloc] initWithHost:host];
        [self.statusController setButtonTitle:SULocalizedString(@"Cancel Update", @"") target:nil action:Nil isDefault:NO];
        [self.statusController beginActionWithTitle:SULocalizedString(@"Installing update...", @"")
                                   maxProgressValue:100 statusText: @""];
        [self.statusController showWindow:self];
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *initialInstallationError = nil;
        if (![installer performInitialInstallation:&initialInstallationError]) {
            SULog(SULogLevelError, @"Failed to perform initial installation with error: %@", initialInstallationError);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showError:initialInstallationError];
                exit(EXIT_FAILURE);
            });
            return;
        }
        
        void(^progressBlock)(double) = ^(double progress){
            dispatch_async(dispatch_get_main_queue(), ^(){
                self.statusController.progressValue = progress * 100.0;
            });
        };

        NSError *finalInstallationError = nil;
        if (![installer performFinalInstallationProgressBlock:progressBlock error:&finalInstallationError]) {
            NSError *underlyingError = [finalInstallationError.userInfo objectForKey:NSUnderlyingErrorKey];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (underlyingError == nil || underlyingError.code != SUInstallationCancelledError) {
                    SULog(SULogLevelError, @"Failed to perform final installation Error: %@", finalInstallationError);
                    [self showError:finalInstallationError];
                }
                exit(EXIT_FAILURE);
            });
            return;
        }
        
        NSString *installationPath = [installer installationPath];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *pathToRelaunch = nil;
            // If the relaunch path is the same as the host bundle path, use the installation path from the installer which may be normalized
            // Otherwise use the requested relaunch path in all other cases
            if ([self.relaunchPath.pathComponents isEqualToArray:host.bundlePath.pathComponents]) {
                pathToRelaunch = installationPath;
            } else {
                pathToRelaunch = self.relaunchPath;
            }
            [self cleanupAndTerminateWithPathToRelaunch:pathToRelaunch];
        });
    });
}

- (void)cleanupAndTerminateWithPathToRelaunch:(NSString *)relaunchPath
{
    self.isTerminating = YES;
    
    dispatch_block_t cleanupAndExit = ^{
        NSError *theError = nil;
        if (![[NSFileManager defaultManager] removeItemAtPath:self.updateFolderPath error:&theError]) {
            SULog(SULogLevelError, @"Couldn't remove update folder: %@.", theError);
        }
        
        [[NSFileManager defaultManager] removeItemAtPath:[[NSBundle mainBundle] bundlePath] error:NULL];
        
        exit(EXIT_SUCCESS);
    };
    
    if (self.shouldRelaunch) {
        // The auto updater can terminate before the newly updated app is finished launching
        // If that happens, the OS may not make the updated app active and frontmost
        // (Or it does become frontmost, but the OS backgrounds it afterwards.. It's some kind of timing/activation issue that doesn't occur all the time)
        // The only remedy I've been able to find is waiting an arbitrary delay before exiting our application
        
        // Don't use -launchApplication: because we may not be launching an application. Eg: it could be a system prefpane
        if (![[NSWorkspace sharedWorkspace] openFile:relaunchPath]) {
            SULog(SULogLevelError, @"Failed to launch %@", relaunchPath);
        }
        
        [self.statusController close];
        
        // Don't even think about hiding the app icon from the dock if we've already shown it
        // Transforming the app back to a background one has a backfiring effect, decreasing the likelihood
        // that the updated app will be brought up front
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SUTerminationTimeDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            cleanupAndExit();
        });
    } else {
        cleanupAndExit();
    }
}

@end

int main(int __unused argc, const char __unused *argv[])
{
    @autoreleasepool
    {
        NSArray *args = [[NSProcessInfo processInfo] arguments];
        if (args.count < 5 || args.count > 7) {
            return EXIT_FAILURE;
        }
        
        NSApplication *application = [NSApplication sharedApplication];

        BOOL shouldShowUI = (args.count > 6) ? [[args objectAtIndex:6] boolValue] : YES;
        if (shouldShowUI) {
            [application activateIgnoringOtherApps:YES];
        }
        
        AppInstaller *appInstaller = [[AppInstaller alloc] initWithHostPath:[args objectAtIndex:1]
                                                               relaunchPath:[args objectAtIndex:2]
                                                            parentProcessId:[[args objectAtIndex:3] intValue]
                                                           updateFolderPath:[args objectAtIndex:4]
                                                             shouldRelaunch:(args.count > 5) ? [[args objectAtIndex:5] boolValue] : YES
                                                               shouldShowUI:shouldShowUI];
        [application setDelegate:appInstaller];
        [application run];
    }

    return EXIT_SUCCESS;
}
