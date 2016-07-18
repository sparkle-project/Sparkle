//
//  InstallerProgressLauncher.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/17/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol InstallerProgressLauncherDelegate <NSObject>

- (void)installerProgressLauncherDidInvalidate;
- (void)installerProgressLauncherDidSubmitJob;

@end

@interface InstallerProgressLauncher : NSObject

- (instancetype)initWithHostBundle:(NSBundle *)hostBundle installerPath:(NSString *)installerPath allowingInteraction:(BOOL)allowingInteraction delegate:(id<InstallerProgressLauncherDelegate>)delegate;

- (void)startListener;

- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
