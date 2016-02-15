//
//  SUUserUpdater.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/14/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUUpdateAlertChoice.h"

@class SUHost, SUUpdatePermissionPromptResult, SUAppcastItem;

@protocol SUVersionDisplay;

@protocol SUUserUpdaterDriver <NSObject>

- (instancetype)initWithHost:(SUHost *)host;

- (void)requestUpdatePermissionWithSystemProfile:(NSArray *)systemProfile reply:(void (^)(SUUpdatePermissionPromptResult *))reply;

- (void)openInfoURLForAppcastItem:(SUAppcastItem *)appcastItem;

- (void)showUserInitiatedUpdateCheckWithCancelCallback:(void (^)(void))cancelUpdateCheck;
- (void)dismissUserInitiatedUpdateCheck;

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem versionDisplayer:(id<SUVersionDisplay>)versionDisplayer reply:(void (^)(SUUpdateAlertChoice))reply;

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

- (void)dismissUpdateInstallation;

@end
