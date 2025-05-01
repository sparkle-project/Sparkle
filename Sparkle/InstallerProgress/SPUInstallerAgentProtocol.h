//
//  SPUInstallerAgentProtocol.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SPUInstallerAgentProtocol

- (void)registerApplicationBundlePath:(NSString *)applicationBundlePath reply:(void (^)(BOOL))reply;

- (void)registerInstallationInfoData:(NSData *)installationInfoData;

- (void)listenForTerminationWithCompletion:(void (^)(void))completionHandler;

- (void)sendTerminationSignal;

- (void)showProgress;

- (void)stopProgress;

- (void)relaunchApplication;

@end

NS_ASSUME_NONNULL_END
