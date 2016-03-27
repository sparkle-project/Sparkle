//
//  SUStandardUserDriverUIDelegate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SUVersionDisplay;

/*!
 A delegate protocol for Sparkle's standard user driver related to user interactions
 */
@protocol SUStandardUserDriverUIDelegate <NSObject>

@optional

/*!
 Called before showing a modal alert window,
 to give the opportunity to hide attached windows that may get in the way.
 */
- (void)userDriverWillShowModalAlert;

/*!
 Called after showing a modal alert window,
 to give the opportunity to hide attached windows that may get in the way.
 */
- (void)userDriverDidShowModalAlert;

/*!
 Returns an object that formats version numbers for display to the user.
 If you don't implement this method or return \c nil,
 the standard version formatter will be used.
 */
- (_Nullable id <SUVersionDisplay>)userDriverRequestsVersionDisplayer;

@end

NS_ASSUME_NONNULL_END
