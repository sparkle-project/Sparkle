//
//  SUPopUpTitlebarUserDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/5/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Sparkle/Sparkle.h>

@class NSWindow;

__attribute__((objc_direct_members)) @interface SUPopUpTitlebarUserDriver : NSObject <SPUUserDriver>

- (instancetype)initWithWindow:(NSWindow *)window;

@end
