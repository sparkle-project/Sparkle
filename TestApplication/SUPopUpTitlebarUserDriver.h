//
//  SUPopUpTitlebarUserDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/5/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Sparkle/Sparkle.h>

@protocol SUStandardUserDriver;

@interface SUPopUpTitlebarUserDriver : NSObject <SUUserDriver, SUStandardUserDriver>

- (instancetype)initWithWindow:(NSWindow *)window delegate:(id<SUStandardUserDriverDelegate>)delegate;

@end
