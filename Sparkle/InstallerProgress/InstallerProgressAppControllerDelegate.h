//
//  InstallerProgressAppControllerDelegate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol InstallerProgressAppControllerDelegate <NSObject>

- (void)applicationDidFinishLaunchingWithTargetBundle:(NSBundle *)bundle;
- (void)applicationWillTerminateAfterDelay;

@end

NS_ASSUME_NONNULL_END
