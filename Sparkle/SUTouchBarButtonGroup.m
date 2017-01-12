//
//  SUTouchBarButtonGroup.m
//  Sparkle
//
//  Created by Yuxin Wang on 05/01/2017.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#import "SUTouchBarButtonGroup.h"

@implementation SUTouchBarButtonGroup

@synthesize buttons = _buttons;

- (instancetype)initByReferencingButtons:(NSArray<NSButton *> *)buttons
{
    if (!(self = [super init]))
        return self;

    NSView *buttonGroup = [NSView new];
    self.view = buttonGroup;
    NSMutableArray *constraints = [NSMutableArray array];
    NSMutableArray *buttonCopies = [NSMutableArray arrayWithCapacity:buttons.count];
    
    for (NSUInteger i = 0; i < buttons.count; i++) {
        NSButton *button = buttons[i];
        NSButton *buttonCopy = [NSButton buttonWithTitle:button.title target:button.target action:button.action];
        buttonCopy.tag = button.tag;
        buttonCopy.enabled = button.enabled;
        
        if (i == 0) {
            buttonCopy.keyEquivalent = @"\r";
        }
        
        buttonCopy.translatesAutoresizingMaskIntoConstraints = NO;
        
        [buttonCopies addObject:buttonCopy];
        [buttonGroup addSubview:buttonCopy];
        
        [constraints addObject:[NSLayoutConstraint constraintWithItem:buttonCopy attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:buttonGroup attribute:NSLayoutAttributeTop multiplier:1.0 constant:0.0]];
        [constraints addObject:[NSLayoutConstraint constraintWithItem:buttonCopy attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:buttonGroup attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0.0]];
        if (i == 0) {
            [constraints addObject:[NSLayoutConstraint constraintWithItem:buttonCopy attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:buttonGroup attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:0.0]];
        } else {
            [constraints addObject:[NSLayoutConstraint constraintWithItem:buttonCopy attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:buttonCopies[i-1] attribute:NSLayoutAttributeLeading multiplier:1.0 constant:(i == 1) ? -8 : -32]];
        }
        if (i == buttons.count - 1) {
            [constraints addObject:[NSLayoutConstraint constraintWithItem:buttonCopy attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:buttonGroup attribute:NSLayoutAttributeLeading multiplier:1.0 constant:0.0]];
        }
    }
    [NSLayoutConstraint activateConstraints:constraints];
    
    _buttons = buttonCopies;
    return self;
}

@end

