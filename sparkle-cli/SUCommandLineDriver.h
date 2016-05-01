//
//  SUCommandLineDriver.h
//  sparkle-cli
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface SUCommandLineDriver : NSObject

- (nullable instancetype)initWithUpdateBundlePath:(NSString *)updateBundlePath applicationBundlePath:(nullable NSString *)applicationBundlePath deferInstallation:(BOOL)deferInstallation verbose:(BOOL)verbose;

- (void)run;

@end

NS_ASSUME_NONNULL_END
