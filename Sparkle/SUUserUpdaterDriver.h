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

#warning Is this really helpful and needed?
typedef NS_ENUM(NSUInteger, SUUpdateInstallationType) {
    SUManualInstallationType,
    SUAutomaticInstallationType
};

@protocol SUUserUpdaterDriver <NSObject>

#warning might need to whitelist class types for systemProfile.. need to test this
- (void)requestUpdatePermissionWithSystemProfile:(NSArray *)systemProfile reply:(void (^)(SUUpdatePermissionPromptResult *))reply;

- (void)showUserInitiatedUpdateCheckWithCancelCallback:(void (^)(void))cancelUpdateCheck;
- (void)dismissUserInitiatedUpdateCheck;

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem versionDisplayer:(id<SUVersionDisplay>)versionDisplayer reply:(void (^)(SUUpdateAlertChoice))reply;

#warning maybe this should take a versionDisplayer too?
- (void)showAutomaticUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem reply:(void (^)(SUAutomaticInstallationChoice))reply;

- (void)showUpdateNotFound;
- (BOOL)showsUpdateNotFoundModally;

- (void)showUpdaterError:(NSError *)error;
- (BOOL)showsUpdateErrorModally;

- (void)showDownloadInitiatedWithCancelCallback:(void (^)(void))cancelDownload;
- (void)showDownloadDidReceiveResponse:(NSURLResponse *)response;
- (void)showDownloadDidReceiveDataOfLength:(NSUInteger)length;
- (void)showDownloadFinishedAndStartedExtractingUpdate;
- (void)showExtractionReceivedProgress:(double)progress;
- (void)showExtractionFinishedAndReadyToInstallAndRelaunch:(void (^)(void))installUpdateAndRelaunch;

- (void)showInstallingUpdate;

- (void)registerForAppTermination:(void (^)(void))applicationWillTerminate;
- (void)unregisterForAppTermination;

- (void)dismissUpdateInstallation:(SUUpdateInstallationType)installationType;

@end
