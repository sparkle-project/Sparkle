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

/*
 * hostPath - path to host (original) application
 * relaunchPath - path to what the host wants to relaunch (default is same as hostPath)
 * hostProcessIdentifier - process identifier of the host before launching us
 * updateFolderPath - path to update folder (i.e, temporary directory containing the new update)
 * shouldRelaunch - indicates if the new installed app should re-launched
 * shouldShowUI - indicates if we should show the status window when installing the update
 */
- (instancetype)initWithHostPath:(NSString *)hostPath relaunchPath:(NSString *)relaunchPath hostProcessIdentifier:(NSNumber *)hostProcessIdentifier updateFolderPath:(NSString *)updateFolderPath shouldRelaunch:(BOOL)shouldRelaunch shouldShowUI:(BOOL)shouldShowUI
{
    if (!(self = [super init])) {
        return nil;
    }
    
    self.hostPath = hostPath;
    self.relaunchPath = relaunchPath;
    self.terminationListener = [[TerminationListener alloc] initWithProcessIdentifier:hostProcessIdentifier];
    self.updateFolderPath = updateFolderPath;
    self.shouldRelaunch = shouldRelaunch;
    self.shouldShowUI = shouldShowUI;
    
    return self;
}

- (void)installAfterHostTermination
{
    [self.terminationListener startListeningWithCompletion:^(BOOL success){
        self.terminationListener = nil;
        
        if (!success) {
            // We should just give up now - should we show an alert though??
            SULog(@"Timed out waiting for target to terminate. Target path is %@", self.hostPath);
            [self cleanupAndExit];
        } else {
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
        }
    }];
}

- (void)install
{
    NSBundle *theBundle = [NSBundle bundleWithPath:self.hostPath];
    SUHost *host = [[SUHost alloc] initWithBundle:theBundle];
    NSString *installationPath = [[host installationPath] copy];
    
    if (self.shouldShowUI) {
        self.statusController = [[SUStatusController alloc] initWithHost:host];
        [self.statusController setButtonTitle:SULocalizedString(@"Cancel Update", @"") target:nil action:Nil isDefault:NO];
        [self.statusController beginActionWithTitle:SULocalizedString(@"Installing update...", @"")
                                   maxProgressValue: 0 statusText: @""];
        [self.statusController showWindow:self];
        [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    }
    
    [SUInstaller
     installFromUpdateFolder:self.updateFolderPath
     overHost:host
     installationPath:installationPath
     versionComparator:[SUStandardVersionComparator defaultComparator]
     completionHandler:^(NSError *error) {
         if (error) {
             SULog(@"Installation Error: %@", error);
             if (self.shouldShowUI) {
                 NSAlert *alert = [[NSAlert alloc] init];
                 alert.messageText = @"";
                 alert.informativeText = [NSString stringWithFormat:@"%@", [error localizedDescription]];
                 [alert runModal];
             }
             exit(EXIT_FAILURE);
         } else {
             NSString *pathToRelaunch = nil;
             // If the installation path differs from the host path, we give higher precedence for it than
             // if the desired relaunch path differs from the host path
             if (![installationPath.pathComponents isEqualToArray:self.hostPath.pathComponents] || [self.relaunchPath.pathComponents isEqualToArray:self.hostPath.pathComponents]) {
                 pathToRelaunch = installationPath;
             } else {
                 pathToRelaunch = self.relaunchPath;
             }
             [self cleanupAndTerminateWithPathToRelaunch:pathToRelaunch];
         }
     }];
}

- (void)cleanupAndExit __attribute__((noreturn))
{
    NSError *theError = nil;
    if (![[NSFileManager defaultManager] removeItemAtPath:self.updateFolderPath error:&theError]) {
        SULog(@"Couldn't remove update folder: %@.", theError);
    }
    
    [[NSFileManager defaultManager] removeItemAtPath:[[NSBundle mainBundle] bundlePath] error:NULL];
    
    exit(EXIT_SUCCESS);
}

- (void)cleanupAndTerminateWithPathToRelaunch:(NSString *)relaunchPath
{
    self.isTerminating = YES;
    
    if (self.shouldRelaunch) {
        // The auto updater can terminate before the newly updated app is finished launching
        // If that happens, the OS may not make the updated app active and frontmost
        // (Or it does become frontmost, but the OS backgrounds it afterwards.. It's some kind of timing/activation issue that doesn't occur all the time)
        // The only remedy I've been able to find is waiting an arbitrary delay before exiting our application
        
        // Don't use -launchApplication: because we may not be launching an application. Eg: it could be a system prefpane
        if (![[NSWorkspace sharedWorkspace] openFile:relaunchPath]) {
            SULog(@"Failed to launch %@", relaunchPath);
        }
        
        [self.statusController close];
        
        // Don't even think about hiding the app icon from the dock if we've already shown it
        // Transforming the app back to a background one has a backfiring effect, decreasing the likelihood
        // that the updated app will be brought up front
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SUTerminationTimeDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self cleanupAndExit];
        });
    } else {
        [self cleanupAndExit];
    }
}

@end
