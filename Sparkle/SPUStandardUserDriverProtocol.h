//
//  SPUStandardUserDriverProtocol.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/5/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SPUStandardUserDriverDelegate;

/*!
 Protocol for Sparkle's standard built-in user driver for updater interactions.
 
 Other user drivers may wish to implement this protocol.
 */
@protocol SPUStandardUserDriverProtocol <NSObject>

/*!
 Readable and writable property for this user driver's delegate
 */
@property (nonatomic, weak, nullable, readonly) id <SPUStandardUserDriverDelegate> delegate;

/*!
 Indicates whether or not an update is in progress as far as the user's perspective is concerned
 
 A typical application may rely on this property for its check for updates menu item validation
 */
@property (nonatomic, readonly) BOOL canCheckForUpdates;

@end
