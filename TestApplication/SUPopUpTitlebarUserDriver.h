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

SPU_OBJC_DIRECT_MEMBERS @interface SUPopUpTitlebarUserDriver : NSObject <SPUUserDriver>

- (instancetype)initWithWindow:(NSWindow *)window;

@end
