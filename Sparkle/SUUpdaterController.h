//
//  SUUpdaterController.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

// Note this class is not intended for XPC or sandboxing
// It's meant to be droppable via Interface Builder as a custom NSObject subclass

@class SUUpdater;

/*!
 A controller class that instantiates a SUUpdater and allows binding UI actions and outlets to it.
 
 This controller's updater targets the application's main bundle, and uses Sparkle's standard user interface.
 Thus it is only suitable under these circumstances. Typically, this class is used by sticking it as a custom NSObject in an Interface Builder nib (probably in MainMenu).
 The controller then kicks off creating an SUUpdater instance and allows hooking up various actions and outlets.
 
 There may be several reasons why this class may not be very suitable for you:
 * You want to defer the instantiation of an SUUpdater, or don't want to be tied into a nib's instantiation, or don't want to use a nib
 * You want to separate Sparkle's updater and user interface into separate processes
 * You don't want to use a convenience class that provides very little glue ;)
 
  */
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
 
 This action checks updates by invoking -[SUUpdater checkForUpdates]
 */
- (IBAction)checkForUpdates:(id)sender;

/*!
 Validates if the menu item for checkForUpdates: can be invoked or not
 
 This validates the menu item by invoking -[SUUpdater updateInProgress]
 */
- (BOOL)validateMenuItem:(NSMenuItem *)item;

@end
