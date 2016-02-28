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

@property (nonatomic, copy) void (^downloadUpdateStatusCompletion)(SUDownloadUpdateStatus);
@property (nonatomic, copy) void (^updateCheckStatusCompletion)(SUUserInitiatedCheckStatus);
@property (nonatomic, copy) void (^applicationTerminationHandler)(SUApplicationTerminationStatus);
@property (nonatomic, copy) void (^checkForUpdateReply)(SUUpdateCheckTimerStatus);

@property (nonatomic) NSTimer *checkUpdateTimer;
@property (nonatomic) BOOL registeredApplicationTermination;

@end

@implementation SULoggerUpdateDriver

@synthesize downloadUpdateStatusCompletion = _downloadUpdateStatusCompletion;
@synthesize updateCheckStatusCompletion = _updateCheckStatusCompletion;
@synthesize applicationTerminationHandler = _applicationTerminationHandler;
@synthesize checkUpdateTimer = _checkUpdateTimer;
@synthesize checkForUpdateReply = _checkForUpdateReply;
@synthesize registeredApplicationTermination = _registeredApplicationTermination;

- (void)startUpdateCheckTimerWithNextTimeInterval:(NSTimeInterval)timeInterval reply:(void (^)(SUUpdateCheckTimerStatus))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.checkForUpdateReply = reply;
        self.checkUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:timeInterval target:self selector:@selector(checkForUpdates:) userInfo:nil repeats:NO];
    });
}

- (void)checkForUpdates:(NSTimer *)__unused timer
{
    if (self.checkForUpdateReply != nil) {
        self.checkForUpdateReply(SUCheckForUpdateNow);
        self.checkForUpdateReply = nil;
    }
}

- (void)_invalidateUpdateCheckTimer
{
    [self.checkUpdateTimer invalidate];
    self.checkUpdateTimer = nil;
    
    if (self.checkForUpdateReply != nil) {
        self.checkForUpdateReply(SUCheckForUpdateWillOccurLater);
        self.checkForUpdateReply = nil;
    }
}

- (void)invalidateUpdateCheckTimer
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _invalidateUpdateCheckTimer];
    });
}

- (void)requestUpdatePermissionWithSystemProfile:(NSArray *)__unused systemProfile reply:(void (^)(SUUpdatePermissionPromptResult *))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"Giving permission to automatically install updates!");
        reply([SUUpdatePermissionPromptResult updatePermissionPromptResultWithChoice:SUAutomaticallyCheck shouldSendProfile:YES]);
    });
}

- (void)showUserInitiatedUpdateCheckWithCompletion:(void (^)(SUUserInitiatedCheckStatus))completionStatusCheck
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"Evil user initiated an update check!");
        self.updateCheckStatusCompletion = completionStatusCheck;
    });
}

- (void)dismissUserInitiatedUpdateCheck
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.updateCheckStatusCompletion != nil) {
            self.updateCheckStatusCompletion(SUUserInitiatedCheckDone);
            self.updateCheckStatusCompletion = nil;
        }
        NSLog(@"Update check is done!");
    });
}

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)__unused appcastItem versionDisplayer:(id<SUVersionDisplay>)__unused versionDisplayer reply:(void (^)(SUUpdateAlertChoice))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"OMG new update was found! Let's install it!");
        reply(SUInstallUpdateChoice);
    });
}

- (void)showAutomaticUpdateFoundWithAppcastItem:(SUAppcastItem *)__unused appcastItem reply:(void (^)(SUAutomaticInstallationChoice))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"OK, requested automatic update permission.. replying..");
        reply(SUInstallLaterChoice);
    });
}

- (void)showUpdateNotFound
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@":( there was no new update");
    });
}

- (void)showUpdaterError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"Update error: %@", error);
    });
}

- (void)showDownloadInitiatedWithCompletion:(void (^)(SUDownloadUpdateStatus))downloadUpdateStatusCompletion
{
    NSLog(@"Downloading update...");
    dispatch_async(dispatch_get_main_queue(), ^{
        self.downloadUpdateStatusCompletion = downloadUpdateStatusCompletion;
    });
}

- (void)showDownloadDidReceiveResponse:(NSURLResponse *)response
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"Download recieved length: %lld", response.expectedContentLength);
    });
}

- (void)showDownloadDidReceiveDataOfLength:(NSUInteger)length
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"Download received progress: %lu", length);
    });
}

- (void)showDownloadFinishedAndStartedExtractingUpdate
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.downloadUpdateStatusCompletion != nil) {
            self.downloadUpdateStatusCompletion(SUDownloadUpdateDone);
            self.downloadUpdateStatusCompletion = nil;
        }
        
        NSLog(@"Download finished.. Extracting..");
    });
}

- (void)showExtractionReceivedProgress:(double)progress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"Extracting progress: %f", progress);
    });
}

- (void)showExtractionFinishedAndReadyToInstallAndRelaunch:(void (^)(SUInstallUpdateStatus))installUpdateHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"Extracting finished.. Letting it install & relaunch..");
        installUpdateHandler(SUInstallAndRelaunchUpdateNow);
    });
}

- (void)showInstallingUpdate
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"Installing update...");
    });
}

- (void)registerApplicationTermination:(void (^)(SUApplicationTerminationStatus))applicationTerminationHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.registeredApplicationTermination = YES;
        
        NSLog(@"Registered for termination, eh?");
        self.applicationTerminationHandler = applicationTerminationHandler;
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
    });
}

- (void)_unregisterApplicationTermination
{
    if (self.registeredApplicationTermination) {
        if (self.applicationTerminationHandler != nil) {
            self.applicationTerminationHandler(SUApplicationStoppedObservingTermination);
            self.applicationTerminationHandler = nil;
        }
        
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationWillTerminateNotification object:nil];
        
        self.registeredApplicationTermination = NO;
    }
}

- (void)unregisterApplicationTermination
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _unregisterApplicationTermination];
    });
}

- (void)applicationWillTerminate:(NSNotification *)__unused note
{
    NSLog(@"Terminating app..");
    if (self.applicationTerminationHandler != nil) {
        NSLog(@"App will terminate");
        self.applicationTerminationHandler(SUApplicationWillTerminate);
        self.applicationTerminationHandler = nil;
    }
}

- (void)terminateApplication
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSApp terminate:nil];
    });
}

- (void)dismissUpdateInstallation
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"Dismissing the installation.");
        
        [self _invalidateUpdateCheckTimer];
        
        if (self.updateCheckStatusCompletion != nil) {
            self.updateCheckStatusCompletion(SUUserInitiatedCheckCancelled);
            self.updateCheckStatusCompletion = nil;
        }
        
        if (self.downloadUpdateStatusCompletion != nil) {
            self.downloadUpdateStatusCompletion(SUDownloadUpdateCancelled);
            self.downloadUpdateStatusCompletion = nil;
        }
        
        [self _unregisterApplicationTermination];
    });
}

@end

@interface SUUpdateSettingsWindowController ()

@property (nonatomic) IBOutlet SUUpdater *updater;

@end

@implementation SUUpdateSettingsWindowController

@synthesize updater = _updater;

- (void)windowDidLoad
{
    self.updater.userUpdaterDriver = [[SUSparkleUserUpdaterDriver alloc] initWithHost:[[SUHost alloc] initWithBundle:[NSBundle mainBundle]] handlesTermination:YES delegate:nil];
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
