//
//  SUInstallerDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SUUpdaterDelegate;
@class SUHost, SUAppcastItem;

@protocol SUInstallerDriverDelegate <NSObject>

- (void)installerDidStartInstalling;
- (void)installerDidExtractUpdateWithProgress:(double)progress;
- (void)installerDidFinishPreparationAndCanInstallSilently:(BOOL)canInstallSilently;
- (void)installerIsRequestingAppTermination;

- (void)installerIsRequestingAbortInstallWithError:(nullable NSError *)error;
- (void)installerDidFailToApplyDeltaUpdate;

@end

@interface SUInstallerDriver : NSObject

- (instancetype)initWithHost:(SUHost *)host cachePath:(NSString *)cachePath sparkleBundle:(NSBundle *)sparkleBundle updater:(id)updater updaterDelegate:(nullable id<SUUpdaterDelegate>)updaterDelegate delegate:(nullable id<SUInstallerDriverDelegate>)delegate;

- (void)extractDownloadPath:(NSString *)downloadPath withUpdateItem:(SUAppcastItem *)updateItem temporaryDirectory:(NSString *)temporaryDirectory completion:(void (^)(NSError * _Nullable))completionHandler;

- (void)installWithToolAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI;

- (void)abortInstall;

@end

NS_ASSUME_NONNULL_END
