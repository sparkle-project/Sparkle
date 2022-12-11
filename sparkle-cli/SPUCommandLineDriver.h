//
//  SUCommandLineDriver.h
//  sparkle-cli
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class SUUpdatePermissionResponse;

@interface SPUCommandLineDriver : NSObject

- (nullable instancetype)initWithUpdateBundlePath:(NSString *)updateBundlePath applicationBundlePath:(nullable NSString *)applicationBundlePath allowedChannels:(NSSet<NSString *> *)allowedChannels customFeedURL:(nullable NSString *)customFeedURL userAgentName:(nullable NSString *)userAgentName updatePermissionResponse:(nullable SUUpdatePermissionResponse *)updatePermissionResponse deferInstallation:(BOOL)deferInstallation interactiveInstallation:(BOOL)interactiveInstallation allowMajorUpgrades:(BOOL)allowMajorUpgrades verbose:(BOOL)verbose __attribute__((objc_direct));

- (void)runAndCheckForUpdatesNow:(BOOL)checkForUpdatesNow __attribute__((objc_direct));

- (void)probeForUpdates __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END
