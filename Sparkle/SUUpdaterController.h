//
//  SUUpdaterController.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

// Note this class is not intended for XPC or sandboxing (or not yet?)
// It's meant to be droppable via Interface Builder as a custom NSObject subclass

@class SUUpdater;

@interface SUUpdaterController : NSObject

@property (nonatomic, readonly) SUUpdater *updater;

/*!
 Explicitly checks for updates and displays a progress dialog while doing so.
 
 This method is meant for a main menu item.
 Connect any menu item to this action in Interface Builder,
 and Sparkle will check for updates and report back its findings verbosely
 when it is invoked.
 */
- (IBAction)checkForUpdates:(id)sender;

@end
