//
//  SUUpdaterQueue.h
//  Sparkle
//
//  Created by Dmytro Tretiakov on 7/31/14.
//
//

#import <Foundation/Foundation.h>

@class SUUpdater;

@interface SUUpdaterQueue : NSObject

- (void)addUpdater:(SUUpdater *)updater;
- (void)removeUpdater:(SUUpdater *)updater;

- (void)checkForUpdates;
- (void)checkForUpdatesInBackground;

@end
