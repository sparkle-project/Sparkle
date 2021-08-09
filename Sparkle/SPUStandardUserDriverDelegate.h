//
//  SPUStandardUserDriverDelegate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/3/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#if __has_feature(modules)
#if __has_warning("-Watimport-in-framework-header")
#pragma clang diagnostic ignored "-Watimport-in-framework-header"
#endif
@import Foundation;
#else
#import <Foundation/Foundation.h>
#endif
#import <Sparkle/SUExport.h>

@protocol SUVersionDisplay;

/**
 A protocol for Sparkle's standard user driver's delegate
 
 This includes methods related to UI interactions
 */
SU_EXPORT @protocol SPUStandardUserDriverDelegate <NSObject>

@optional

/**
 Called before showing a modal alert window,
 to give the opportunity to hide attached windows that may get in the way.
 */
- (void)standardUserDriverWillShowModalAlert;

/**
 Called after showing a modal alert window,
 to give the opportunity to hide attached windows that may get in the way.
 */
- (void)standardUserDriverDidShowModalAlert;

/**
 Returns an object that formats version numbers for display to the user.
 If you don't implement this method or return @c nil, the standard version formatter will be used.
 */
- (_Nullable id <SUVersionDisplay>)standardUserDriverRequestsVersionDisplayer;

@end
