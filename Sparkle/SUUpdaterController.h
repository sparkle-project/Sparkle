//
//  SUUpdaterController.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

// Note this class is not intended for XPC or sandboxing (or not yet?)
// It's meant to be droppable via Interface Builder as a custom NSObject subclass

@class SUUpdater;

@interface SUUpdaterController : NSObject

/*!
 Accessible property for the updater. Some properties on the updater can be binded via KVO
 */
@property (nonatomic, readonly) SUUpdater *updater;

/*!
 Explicitly checks for updates and displays a progress dialog while doing so.
 
 This method is meant for a main menu item.
 Connect any menu item to this action in Interface Builder,
 and Sparkle will check for updates and report back its findings verbosely
 when it is invoked.
 */
- (IBAction)checkForUpdates:(id)sender;

/*!
 Validates if the menu item for checkForUpdates: can be invoked or not
 */
- (BOOL)validateMenuItem:(NSMenuItem *)item;

@end
