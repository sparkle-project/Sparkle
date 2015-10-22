//
//  SUUpdater_Private.h
//  Sparkle
//
//  Created by Andy Matuschak on 5/9/11.
//  Copyright 2011 Andy Matuschak. All rights reserved.
//

#import "SUUpdater.h"

@class SUBasicUpdateDriver, SUHost;

@interface SUUpdater (Private)

@property (readonly) BOOL mayUpdateAndRestart;
@property (readonly) SUBasicUpdateDriver *basicDriver;
@property (readonly) SUHost *host;

@end

@protocol SUPrivateUpdaterDelegate <SUUpdaterDelegate>
@optional

- (void)updaterWillStartUpdateProcess:(SUUpdater *)updater;
- (void)updaterDidEndUpdateProcess:(SUUpdater *)updater;

@end
