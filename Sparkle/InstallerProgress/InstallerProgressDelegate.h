//
//  InstallerProgressDelegate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol InstallerProgressDelegate <NSObject>

- (void)installerProgressShouldDisplayWithBundle:(NSBundle *)bundle;
- (void)installerProgressShouldStop;

@end

NS_ASSUME_NONNULL_END
