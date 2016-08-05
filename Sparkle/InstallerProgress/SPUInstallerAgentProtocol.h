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

- (void)registerRelaunchBundlePath:(NSString *)relaunchBundlePath reply:(void (^)(NSNumber * _Nullable processIdentifier))reply;

- (void)registerInstallationInfoData:(NSData *)installationInfoData;

- (void)showProgress;

- (void)stopProgress;

- (void)relaunchPath:(NSString *)pathToRelaunch;

@end

NS_ASSUME_NONNULL_END
