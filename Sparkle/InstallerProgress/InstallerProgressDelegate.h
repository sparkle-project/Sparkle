//
//  InstallerProgressDelegate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUHost;

@protocol InstallerProgressDelegate <NSObject>

- (void)loadLocalizationStringsFromHost:(SUHost *)host;
- (void)installerProgressShouldDisplayWithHost:(SUHost *)host;
- (void)installerProgressShouldStop;

@end

NS_ASSUME_NONNULL_END
