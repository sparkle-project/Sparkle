//
//  SUUpdateSettingsWindowController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/25/15.
//  Copyright (c) 2015 Sparkle Project. All rights reserved.
//

#import "SUUpdateSettingsWindowController.h"
#import <Sparkle/Sparkle.h>

#import "SUUserUpdaterDriver.h"

@interface SULoggerUpdateDriver : NSObject <SUUserUpdaterDriver>

@property (nonatomic, copy) void (^applicationWillTerminate)(void);

@end

@implementation SULoggerUpdateDriver

@synthesize applicationWillTerminate = _applicationWillTerminate;

- (void)requestUpdatePermissionWithSystemProfile:(NSArray *)__unused systemProfile reply:(void (^)(SUUpdatePermissionPromptResult *))reply
{
    NSLog(@"Giving permission to automatically install updates!");
    reply([SUUpdatePermissionPromptResult updatePermissionPromptResultWithChoice:SUAutomaticallyCheck shouldSendProfile:YES]);
}

- (void)showUserInitiatedUpdateCheckWithCancelCallback:(void (^)(void))__unused cancelUpdateCheck
{
    NSLog(@"Evil user initiated an update check!");
}

- (void)dismissUserInitiatedUpdateCheck
{
    NSLog(@"Update check is done!");
}

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)__unused appcastItem versionDisplayer:(id<SUVersionDisplay>)__unused versionDisplayer reply:(void (^)(SUUpdateAlertChoice))reply
{
    NSLog(@"OMG new update was found! Let's install it!");
    reply(SUInstallUpdateChoice);
}

- (void)showAutomaticUpdateFoundWithAppcastItem:(SUAppcastItem *)__unused appcastItem reply:(void (^)(SUAutomaticInstallationChoice))reply
{
    NSLog(@"OK, requested automatic update permission.. replying..");
    reply(SUInstallLaterChoice);
}

- (void)showUpdateNotFound
{
    NSLog(@":( there was no new update");
}

- (void)showUpdaterError:(NSError *)error
{
    NSLog(@"Update error: %@", error);
}

- (void)showDownloadInitiatedWithCancelCallback:(void (^)(void))__unused cancelDownload
{
    NSLog(@"Downloading update...");
}

- (void)showDownloadDidReceiveResponse:(NSURLResponse *)response
{
    NSLog(@"Download recieved length: %lld", response.expectedContentLength);
}

- (void)showDownloadDidReceiveDataOfLength:(NSUInteger)length
{
    NSLog(@"Download received progress: %lu", length);
}

- (void)showDownloadFinishedAndStartedExtractingUpdate
{
    NSLog(@"Download finished.. Extracting..");
}

- (void)showExtractionReceivedProgress:(double)progress
{
    NSLog(@"Extracting progress: %f", progress);
}

- (void)showExtractionFinishedAndReadyToInstallAndRelaunch:(void (^)(void))installUpdateAndRelaunch
{
    NSLog(@"Extracting finished.. Letting it install & relaunch..");
    installUpdateAndRelaunch();
}

- (void)showInstallingUpdate
{
    NSLog(@"Installing update...");
}

- (void)registerForAppTermination:(void (^)(void))applicationWillTerminate
{
    NSLog(@"Registered for termination, eh?");
    self.applicationWillTerminate = applicationWillTerminate;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
}

- (void)unregisterForAppTermination
{
    self.applicationWillTerminate = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationWillTerminateNotification object:nil];
}

- (void)applicationWillTerminate:(NSNotification *)__unused note
{
    NSLog(@"Terminating app..");
    if (self.applicationWillTerminate) {
        NSLog(@"App will terminate");
        self.applicationWillTerminate();
    }
}

- (void)terminateApplication
{
    [NSApp terminate:nil];
}

- (void)dismissUpdateInstallation
{
    NSLog(@"Dismissing the installation.");
}

@end

@interface SUUpdateSettingsWindowController ()

@property (nonatomic) IBOutlet SUUpdater *updater;

@end

@implementation SUUpdateSettingsWindowController

@synthesize updater = _updater;

- (void)windowDidLoad
{
    self.updater.userUpdaterDriver = [[SUSparkleUserUpdaterDriver alloc] initWithHost:[[SUHost alloc] initWithBundle:[NSBundle mainBundle]]];
    //self.updater.userUpdaterDriver = [[SULoggerUpdateDriver alloc] init];
}

- (NSString *)windowNibName
{
    return NSStringFromClass([self class]);
}

- (IBAction)checkForUpdates:(id __unused)sender
{
    [self.updater checkForUpdates:nil];
}

@end
