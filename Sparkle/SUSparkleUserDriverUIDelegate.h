//
//  SUSparkleUserDriverUIDelegate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SUUserDriver, SUVersionDisplay;

/*!
 A delegate protocol for Sparkle's user driver related to user interactions
 */
@protocol SUSparkleUserDriverUIDelegate <NSObject>

@optional

/*!
 Called before showing a modal alert window,
 to give the opportunity to hide attached windows that may get in the way.
 
 @param userDriver The user driver instance.
 */
- (void)userDriverWillShowModalAlert:(id <SUUserDriver>)userDriver;

/*!
 Called after showing a modal alert window,
 to give the opportunity to hide attached windows that may get in the way.
 
 @param userDriver The user driver instance.
 */
- (void)userDriverDidShowModalAlert:(id <SUUserDriver>)userDriver;

/*!
 Returns an object that formats version numbers for display to the user.
 If you don't implement this method or return \c nil,
 the standard version formatter will be used.
 \param userDriver The user driver instance.
 */
- (_Nullable id <SUVersionDisplay>)versionDisplayerForUserDriver:(id <SUUserDriver>)userDriver;

@end

NS_ASSUME_NONNULL_END
