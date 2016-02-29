//
//  SUUserUpdater.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/14/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUUpdateAlertChoice.h"
#import "SUAutomaticInstallationChoice.h"

@class SUUpdatePermissionPromptResult, SUAppcastItem;

@protocol SUVersionDisplay;
@protocol SUUserUpdaterDriver;

typedef NS_ENUM(NSUInteger, SUUpdateCheckTimerStatus) {
    SUCheckForUpdateNow,
    SUCheckForUpdateWillOccurLater
};

typedef NS_ENUM(NSUInteger, SUUserInitiatedCheckStatus) {
    SUUserInitiatedCheckDone,
    SUUserInitiatedCheckCancelled
};

typedef NS_ENUM(NSUInteger, SUDownloadUpdateStatus) {
    SUDownloadUpdateDone,
    SUDownloadUpdateCancelled
};

typedef NS_ENUM(NSUInteger, SUApplicationTerminationStatus) {
    SUApplicationWillTerminate,
    SUApplicationStoppedObservingTermination
};

typedef NS_ENUM(NSUInteger, SUSystemPowerOffStatus) {
    SUSystemWillPowerOff,
    SUStoppedObservingSystemPowerOff
};

typedef NS_ENUM(NSUInteger, SUInstallUpdateStatus) {
    SUInstallAndRelaunchUpdateNow,
    SUCancelUpdateInstallation
};

@protocol SUUserUpdaterDriverDelegate <NSObject>

@optional

- (BOOL)responsibleForInitiatingUpdateCheckForUserDriver:(id <SUUserUpdaterDriver>)userUpdaterDriver;
- (void)initiateUpdateCheckForUserDriver:(id <SUUserUpdaterDriver>)userUpdaterDriver;

- (void)userUpdaterDriverWillShowModalAlert:(id <SUUserUpdaterDriver>)userUpdaterDriver;
- (void)userUpdaterDriverDidShowModalAlert:(id <SUUserUpdaterDriver>)userUpdaterDriver;

@end

@protocol SUUserUpdaterDriver <NSObject>

@property (nonatomic, readonly, weak) id <SUUserUpdaterDriverDelegate> delegate;

- (void)showUpdateInProgress:(BOOL)isUpdateInProgress;

- (void)startUpdateCheckTimerWithNextTimeInterval:(NSTimeInterval)timeInterval reply:(void (^)(SUUpdateCheckTimerStatus))reply;
- (void)invalidateUpdateCheckTimer;

- (void)requestUpdatePermissionWithSystemProfile:(NSArray *)systemProfile reply:(void (^)(SUUpdatePermissionPromptResult *))reply;

- (void)showUserInitiatedUpdateCheckWithCompletion:(void (^)(SUUserInitiatedCheckStatus))updateCheckStatusCompletion;
- (void)dismissUserInitiatedUpdateCheck;

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem versionDisplayer:(id<SUVersionDisplay>)versionDisplayer reply:(void (^)(SUUpdateAlertChoice))reply;

#warning maybe this should take a versionDisplayer too?
- (void)showAutomaticUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem reply:(void (^)(SUAutomaticInstallationChoice))reply;

- (void)showUpdateNotFound;
- (void)showUpdaterError:(NSError *)error;

- (void)showDownloadInitiatedWithCompletion:(void (^)(SUDownloadUpdateStatus))downloadUpdateStatusCompletion;
- (void)showDownloadDidReceiveResponse:(NSURLResponse *)response;
- (void)showDownloadDidReceiveDataOfLength:(NSUInteger)length;
- (void)showDownloadFinishedAndStartedExtractingUpdate;
- (void)showExtractionReceivedProgress:(double)progress;
- (void)showExtractionFinishedAndReadyToInstallAndRelaunch:(void (^)(SUInstallUpdateStatus))installUpdateHandler;

- (void)showInstallingUpdate;

- (void)registerApplicationTermination:(void (^)(SUApplicationTerminationStatus))applicationTerminationHandler;
- (void)unregisterApplicationTermination;
- (void)terminateApplication;

- (void)registerSystemPowerOff:(void (^)(SUSystemPowerOffStatus))systemPowerOffHandler;
- (void)unregisterSystemPowerOff;

- (void)dismissUpdateInstallation;

@end
