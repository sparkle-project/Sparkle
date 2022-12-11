//
//  SPUInstallerDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SPUUpdaterDelegate;
@class SUHost, SUAppcastItem, SPUDownloadedUpdate;

@protocol SPUInstallerDriverDelegate <NSObject>

- (void)installerDidStartInstallingWithApplicationTerminated:(BOOL)applicationTerminated;
- (void)installerDidStartExtracting;
- (void)installerDidExtractUpdateWithProgress:(double)progress;
- (void)installerDidFinishPreparationAndWillInstallImmediately:(BOOL)willInstallImmediately silently:(BOOL)willInstallSilently;
- (void)installerWillFinishInstallationAndRelaunch:(BOOL)relaunch;
- (void)installerDidFinishInstallationAndRelaunched:(BOOL)relaunch acknowledgement:(void(^)(void))acknowledgement;

- (void)installerIsRequestingAbortInstallWithError:(nullable NSError *)error;
- (void)installerDidFailToApplyDeltaUpdate;

@end

@interface SPUInstallerDriver : NSObject

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle updater:(id)updater updaterDelegate:(nullable id<SPUUpdaterDelegate>)updaterDelegate delegate:(nullable id<SPUInstallerDriverDelegate>)delegate __attribute__((objc_direct));

- (void)resumeInstallingUpdateWithUpdateItem:(SUAppcastItem *)updateItem systemDomain:(BOOL)systemDomain __attribute__((objc_direct));

- (void)setUpdateWillInstallHandler:(void (^)(void))updateWillInstallHandler __attribute__((objc_direct));

- (void)extractDownloadedUpdate:(SPUDownloadedUpdate *)downloadedUpdate silently:(BOOL)silently completion:(void (^)(NSError * _Nullable))completionHandler __attribute__((objc_direct));

- (void)installWithToolAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI __attribute__((objc_direct));

- (void)cancelUpdate __attribute__((objc_direct));

- (void)abortInstall __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END
