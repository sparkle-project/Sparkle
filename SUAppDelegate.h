//
//  SUAppDelegate.h
//  Sparkle
//
//  Created by Dmytro Tretiakov on 8/1/14.
//
//

#import <Foundation/Foundation.h>

@class SUUpdater;
@class SUUpdaterQueue;

@interface SUAppDelegate : NSObject

@property (nonatomic, retain) IBOutlet SUUpdater *updater;
@property (nonatomic, retain) SUUpdaterQueue *updaterQueue;

@end
