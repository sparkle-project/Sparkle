//
//  SUStandardUpdaterController.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class SUUpdater;
@protocol SUUserDriver, SUStandardUserDriver, SUUpdaterDelegate, SUStandardUserDriverDelegate;

/*!
 A controller class that instantiates a SUUpdater and allows binding UI to it.
 
 This class is meant to be instantiated in a nib. When doing so, the controller's updater target's the application's main bundle,
 and uses Sparkle's standard user interface. Typically, this class is used by sticking it as a custom NSObject subclass in an Interface Builder nib (probably in MainMenu).
 
 The controller creates an SUUpdater instance and allows hooking up the check for updates action and menu item validation. It also allows hooking
 up the updater's and user driver's delegates.
 
 This controller class may not be valuable to you if:
 * You want to control or defer the instantiation of an SUUpdater, or don't want to be tied into a nib's instantiation, or don't want to use a nib
 * You want to target a bundle that's not the main bundle
 * You want to separate Sparkle's updater and user interface into separate processes
 * You want to provide a custom user interface, or perhaps one that provides little-to-none
 * You don't want to use a convenience class that provides very little glue ;)
 
  */
@interface SUStandardUpdaterController : NSObject

/*!
 Initializes a new updater controller instance using a provided updater and user driver.
 
 Typically this class is instantiated in a nib, thus this method is not usually used.
 */
- (instancetype)initWithUpdater:(SUUpdater *)updater userDriver:(id<SUUserDriver, SUStandardUserDriver>)userDriver;

/*!
 Interface builder outlet for the updater's delegate.
 
 This property should only be set using Interface Builder by creating a connection using the outlet
 */
@property (nonatomic, weak, nullable) IBOutlet id<SUUpdaterDelegate> updaterDelegate;

/*!
 Interface builder outlet for the user driver's delegate.
 
 This property should only be set using Interface Builder by creating a connection using the outlet
 */
@property (nonatomic, weak, nullable) IBOutlet id<SUStandardUserDriverDelegate> userDriverDelegate;

/*!
 Accessible property for the updater. Some properties on the updater can be binded via KVO
 
 This is nil before being awoken from a nib
 */
@property (nonatomic, readonly, nullable) SUUpdater *updater;

/*!
 Accessible property for the updater's user driver.
 
 This is nil before being awoken from a nib
 */
@property (nonatomic, readonly, nullable) id <SUStandardUserDriver> userDriver;

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
 
 This validates the menu item by checking -[SUStandardUserDriver updateInProgress]
 */
- (BOOL)validateMenuItem:(NSMenuItem *)item;

@end

NS_ASSUME_NONNULL_END
