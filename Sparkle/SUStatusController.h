//
//  SUStatusController.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/14/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS || !BUILDING_SPARKLE

#ifndef SUSTATUSCONTROLLER_H
#define SUSTATUSCONTROLLER_H

#import <Cocoa/Cocoa.h>

@class SUHost;
__attribute__((objc_direct_members)) @interface SUStatusController : NSWindowController

@property (nonatomic, copy, direct) NSString *statusText;
@property (nonatomic, direct) double progressValue;
@property (nonatomic, direct) double maxProgressValue;
@property (nonatomic, getter=isButtonEnabled, direct) BOOL buttonEnabled;

- (instancetype)initWithHost:(SUHost *)aHost windowTitle:(NSString *)windowTitle centerPointValue:(NSValue *)centerPointValue minimizable:(BOOL)minimizable closable:(BOOL)closable;

// Pass 0 for the max progress value to get an indeterminate progress bar.
// Pass nil for the status text to not show it.
- (void)beginActionWithTitle:(NSString *)title maxProgressValue:(double)maxProgressValue statusText:(NSString *)statusText;

// If isDefault is YES, the button's key equivalent will be \r.
- (void)setButtonTitle:(NSString *)buttonTitle target:(id)target action:(SEL)action isDefault:(BOOL)isDefault;

@end

#endif

#endif
