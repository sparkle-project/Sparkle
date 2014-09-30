//
//  SUUpdaterQueue.h
//  Sparkle
//
//  Created by Dmytro Tretiakov on 7/31/14.
//
//

@class SUUpdater;

@interface SUUpdaterQueue : NSObject

- (void)addUpdater:(SUUpdater *)updater;
- (void)removeUpdater:(SUUpdater *)updater;

- (void)checkForUpdates;
- (void)checkForUpdatesInBackground;

@end
