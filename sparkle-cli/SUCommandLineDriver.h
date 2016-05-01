//
//  SUCommandLineDriver.h
//  sparkle-cli
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class SUUpdatePermissionPromptResult;

@interface SUCommandLineDriver : NSObject

- (nullable instancetype)initWithUpdateBundlePath:(NSString *)updateBundlePath applicationBundlePath:(nullable NSString *)applicationBundlePath updatePermission:(nullable SUUpdatePermissionPromptResult *)updatePermission deferInstallation:(BOOL)deferInstallation verbose:(BOOL)verbose;

- (void)runAndCheckForUpdatesNow:(BOOL)checkForUpdatesNow;

@end

NS_ASSUME_NONNULL_END
