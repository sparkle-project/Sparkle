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
@interface SUStatusController : NSWindowController

// These three properties are connected via bindings
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic) double progressValue;
@property (nonatomic) double maxProgressValue;

@property (nonatomic, getter=isButtonEnabled, direct) BOOL buttonEnabled;

- (instancetype)initWithHost:(SUHost *)aHost windowTitle:(NSString *)windowTitle centerPointValue:(NSValue *)centerPointValue minimizable:(BOOL)minimizable closable:(BOOL)closable SPU_OBJC_DIRECT;

// Pass 0 for the max progress value to get an indeterminate progress bar.
// Pass nil for the status text to not show it.
- (void)beginActionWithTitle:(NSString *)title maxProgressValue:(double)maxProgressValue statusText:(NSString *)statusText SPU_OBJC_DIRECT;

// If isDefault is YES, the button's key equivalent will be \r.
- (void)setButtonTitle:(NSString *)buttonTitle target:(id)target action:(SEL)action isDefault:(BOOL)isDefault accessibilityIdentifier:(NSString *)accessibilityIdentifier SPU_OBJC_DIRECT;

// -showWindow: is internally buffered so that the window appears only after a short
// delay so a fast-completing operation never causes a flicker. If -close is
// called before the delay elapses, the window never appears at all. Calling
// -showWindow: on an already-visible window brings it to front normally.
- (void)showWindow:(id)sender;

// Close the window, observing an internal minimum display time. completion
// runs once the window has actually closed — immediately if the window isn't
// on screen (or has been visible long enough), or after the remaining time
// otherwise. The userCancelled flag is YES if the close was expedited by
// -closeImmediately (i.e., the user explicitly cancelled); NO if the
// minimum-display timer elapsed normally.
- (void)closeWithCompletionBlock:(void (^)(BOOL userCancelled))completion SPU_OBJC_DIRECT;

// Close the window now. If a deferred close scheduled by
// -closeWithCompletionBlock: is still waiting out the minimum-display time,
// fire its completion now with userCancelled=YES. Returns YES if a pending
// completion fired (so the caller knows the completion's cleanup ran);
// returns NO if there was no pending completion (caller is responsible for
// any state cleanup that would have happened in the completion).
- (BOOL)closeImmediately SPU_OBJC_DIRECT;

@end

#endif

#endif
