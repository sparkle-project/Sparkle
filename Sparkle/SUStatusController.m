//
//  SUStatusController.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/14/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS || !BUILDING_SPARKLE

#import "SUStatusController.h"
#import "SUHost.h"
#import "SUApplicationInfo.h"
#import "SULocalizations.h"
#import "SUTouchBarButtonGroup.h"

static NSString *const SUStatusControllerTouchBarIdentifier = @"" SPARKLE_BUNDLE_IDENTIFIER ".SUStatusController";

@interface SUStatusController () <NSTouchBarDelegate>

// These properties are used for bindings
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *buttonTitle;

@end

@implementation SUStatusController
{
    NSValue *_centerPointValue;
    NSString *_title;
    NSString *_buttonTitle;
    SUHost *_host;
    NSButton *_touchBarButton;

    NSTextField *_titleField;
    NSButton *_actionButton;
    NSProgressIndicator *_progressBar;
}

@synthesize title = _title;
@synthesize buttonTitle = _buttonTitle;
@synthesize progressValue = _progressValue;
@synthesize maxProgressValue = _maxProgressValue;
@synthesize statusText = _statusText;

- (instancetype)initWithHost:(SUHost *)aHost windowTitle:(NSString *)windowTitle centerPointValue:(NSValue *)centerPointValue minimizable:(BOOL)minimizable closable:(BOOL)closable
{
    NSWindow *window;
    NSImageView *imageView;
    NSTextField *titleField;
    NSProgressIndicator *progressBar;
    NSButton *actionButton;
    NSTextField *statusTextField;
    {
        NSWindowStyleMask styleMask = NSWindowStyleMaskTitled;
        if (minimizable) {
            styleMask |= NSWindowStyleMaskMiniaturizable;
        }
        if (closable) {
            styleMask |= NSWindowStyleMaskClosable;
        }
        
        window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 107) styleMask:styleMask backing:NSBackingStoreBuffered defer:NO];
        window.identifier = @"SUStatus";
        window.title = windowTitle;
        window.releasedWhenClosed = NO;
        window.allowsToolTipsWhenApplicationIsInactive = NO;
        window.autorecalculatesKeyViewLoop = NO;
        // Don't let this window make other active windows exit in Stage Manager
        window.collectionBehavior = NSWindowCollectionBehaviorFullScreenAuxiliary;
        window.contentMinSize = NSMakeSize(213, 107);

        NSView *contentView = window.contentView;

        imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        imageView.refusesFirstResponder = YES;
        imageView.imageAlignment = NSImageAlignLeft;
        imageView.imageScaling = NSImageScaleAxesIndependently;
        imageView.image = [SUApplicationInfo bestIconForHost:aHost];
        [contentView addSubview:imageView];

        NSView *statusContainerView = [[NSView alloc] initWithFrame:NSZeroRect];
        statusContainerView.translatesAutoresizingMaskIntoConstraints = NO;
        [contentView addSubview:statusContainerView];

        titleField = [NSTextField labelWithString:@""];
        titleField.translatesAutoresizingMaskIntoConstraints = NO;
        titleField.focusRingType = NSFocusRingTypeNone;
        titleField.font = [NSFont boldSystemFontOfSize:[NSFont systemFontSize]];
        titleField.textColor = [NSColor controlTextColor];
        [titleField setContentHuggingPriority:750 forOrientation:NSLayoutConstraintOrientationVertical];
        // Don't let the title string line wrap
        [titleField setContentCompressionResistancePriority:1000 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [statusContainerView addSubview:titleField];

        progressBar = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
        progressBar.translatesAutoresizingMaskIntoConstraints = NO;
        progressBar.wantsLayer = YES;
        progressBar.style = NSProgressIndicatorStyleBar;
        progressBar.indeterminate = YES;
        progressBar.maxValue = 100;
        [progressBar setContentHuggingPriority:750 forOrientation:NSLayoutConstraintOrientationVertical];
        [progressBar setUsesThreadedAnimation:YES];
        [statusContainerView addSubview:progressBar];

        actionButton = [NSButton buttonWithTitle:@"" target:nil action:NULL];
        actionButton.translatesAutoresizingMaskIntoConstraints = NO;
        if (@available(macOS 26, *)) {
            actionButton.controlSize = NSControlSizeLarge;
        }
        [actionButton setContentHuggingPriority:750 forOrientation:NSLayoutConstraintOrientationVertical];
        actionButton.accessibilityIdentifier = @"SUStatusButton";
        [contentView addSubview:actionButton];

        statusTextField = [NSTextField labelWithString:@""];
        [statusTextField setFont:[NSFont monospacedDigitSystemFontOfSize:0 weight:NSFontWeightRegular]];
        statusTextField.translatesAutoresizingMaskIntoConstraints = NO;
        statusTextField.focusRingType = NSFocusRingTypeNone;
        statusTextField.textColor = [NSColor controlTextColor];
        [statusTextField setContentHuggingPriority:750 forOrientation:NSLayoutConstraintOrientationVertical];
        // Make horizontal compression resistance required for the status text field
        [statusTextField setContentCompressionResistancePriority:1000 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [contentView addSubview:statusTextField];

        [NSLayoutConstraint activateConstraints:@[
            // Status container's internal layout
            [NSLayoutConstraint constraintWithItem:statusContainerView attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:titleField attribute:NSLayoutAttributeTrailing multiplier:1 constant:0],
            [NSLayoutConstraint constraintWithItem:statusContainerView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:progressBar attribute:NSLayoutAttributeBottom multiplier:1 constant:0],
            [NSLayoutConstraint constraintWithItem:titleField attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:statusContainerView attribute:NSLayoutAttributeTop multiplier:1 constant:0],
            [NSLayoutConstraint constraintWithItem:statusContainerView attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:progressBar attribute:NSLayoutAttributeTrailing multiplier:1 constant:0],
            [NSLayoutConstraint constraintWithItem:titleField attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:statusContainerView attribute:NSLayoutAttributeLeading multiplier:1 constant:0],
            [NSLayoutConstraint constraintWithItem:progressBar attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:statusContainerView attribute:NSLayoutAttributeLeading multiplier:1 constant:0],
            [NSLayoutConstraint constraintWithItem:progressBar attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:titleField attribute:NSLayoutAttributeBottom multiplier:1 constant:8],

            // imageView
            [imageView.widthAnchor constraintEqualToConstant:64],
            [imageView.heightAnchor constraintEqualToConstant:64],
            [NSLayoutConstraint constraintWithItem:imageView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:contentView attribute:NSLayoutAttributeTop multiplier:1 constant:4],
            [NSLayoutConstraint constraintWithItem:imageView attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:contentView attribute:NSLayoutAttributeLeading multiplier:1 constant:20],

            // statusContainerView position
            [NSLayoutConstraint constraintWithItem:statusContainerView attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:imageView attribute:NSLayoutAttributeCenterY multiplier:1 constant:0],
            [NSLayoutConstraint constraintWithItem:statusContainerView attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:imageView attribute:NSLayoutAttributeTrailing multiplier:1 constant:8],
            [NSLayoutConstraint constraintWithItem:contentView attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:statusContainerView attribute:NSLayoutAttributeTrailing multiplier:1 constant:20],

            // statusTextField position
            [NSLayoutConstraint constraintWithItem:statusTextField attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:imageView attribute:NSLayoutAttributeTrailing multiplier:1 constant:8],
            [NSLayoutConstraint constraintWithItem:statusTextField attribute:NSLayoutAttributeFirstBaseline relatedBy:NSLayoutRelationEqual toItem:actionButton attribute:NSLayoutAttributeFirstBaseline multiplier:1 constant:0],

            // actionButton position
            [NSLayoutConstraint constraintWithItem:actionButton attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:statusContainerView attribute:NSLayoutAttributeBottom multiplier:1 constant:8],
            [NSLayoutConstraint constraintWithItem:contentView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:actionButton attribute:NSLayoutAttributeBottom multiplier:1 constant:20],
            [NSLayoutConstraint constraintWithItem:actionButton attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:statusTextField attribute:NSLayoutAttributeTrailing multiplier:1 constant:25],
            [NSLayoutConstraint constraintWithItem:contentView attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:actionButton attribute:NSLayoutAttributeTrailing multiplier:1 constant:20],
            [actionButton.widthAnchor constraintGreaterThanOrEqualToConstant:100],
        ]];
    }

    self = [super initWithWindow:window];
	if (self != nil)
	{
        _host = aHost;
        _titleField = titleField;
        _actionButton = actionButton;
        _progressBar = progressBar;
        [self setShouldCascadeWindows:NO];
        
        // Finish setting up bindings
        {
            NSRect windowFrame = window.frame;
            
            if (centerPointValue != nil) {
                NSPoint centerPoint = centerPointValue.pointValue;
                [window setFrameOrigin:NSMakePoint(centerPoint.x - windowFrame.size.width / 2.0, centerPoint.y - windowFrame.size.height / 2.0)];
            } else {
                [window center];
            }

            [titleField bind:NSValueBinding toObject:self withKeyPath:@"title" options:nil];
            [progressBar bind:NSMaxValueBinding toObject:self withKeyPath:@"maxProgressValue" options:nil];
            [progressBar bind:NSValueBinding toObject:self withKeyPath:@"progressValue" options:nil];
            [actionButton bind:NSTitleBinding toObject:self withKeyPath:@"buttonTitle" options:nil];
            [statusTextField bind:NSValueBinding toObject:self withKeyPath:@"statusText" options:nil];
            [statusTextField bind:NSHiddenBinding toObject:self withKeyPath:@"statusText" options:@{NSValueTransformerNameBindingOption: NSIsNilTransformerName}];
        }
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ <%@>", [self class], _host.bundlePath];
}

- (void)beginActionWithTitle:(NSString *)aTitle maxProgressValue:(double)aMaxProgressValue statusText:(NSString *)aStatusText
{
    self.title = aTitle;

    self.maxProgressValue = aMaxProgressValue;
    self.statusText = aStatusText;
}

- (void)setButtonTitle:(NSString *)aButtonTitle target:(id)target action:(SEL)action isDefault:(BOOL)isDefault accessibilityIdentifier:(NSString *)accessibilityIdentifier
{
    self.buttonTitle = aButtonTitle;
    _actionButton.accessibilityIdentifier = [accessibilityIdentifier copy];

    [self window];
    [_actionButton sizeToFit];
    // Except we're going to add 15 px for padding.
    [_actionButton setFrameSize:NSMakeSize(_actionButton.frame.size.width + 15, _actionButton.frame.size.height)];
    // Now we have to move it over so that it's always 15px from the side of the window.
    [_actionButton setFrameOrigin:NSMakePoint([[self window] frame].size.width - 15 - _actionButton.frame.size.width, _actionButton.frame.origin.y)];
    // Redisplay superview to clean up artifacts
    [[_actionButton superview] display];

    [_actionButton setTarget:target];
    [_actionButton setAction:action];
    [_actionButton setKeyEquivalent:isDefault ? @"\r" : @""];
    
    // False warning
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-repeated-use-of-weak"
    _touchBarButton.target = _actionButton.target;
#pragma clang diagnostic pop
    _touchBarButton.action = _actionButton.action;
    _touchBarButton.keyEquivalent = _actionButton.keyEquivalent;

    // 06/05/2008 Alex: Avoid a crash when cancelling during the extraction
    [self setButtonEnabled:(target != nil)];
}

- (BOOL)progressBarShouldAnimate
{
    return YES;
}

- (void)setButtonEnabled:(BOOL)enabled
{
    [_actionButton setEnabled:enabled];
}

- (BOOL)isButtonEnabled
{
    return [_actionButton isEnabled];
}

- (void)setMaxProgressValue:(double)value
{
	if (value < 0.0) value = 0.0;
    _maxProgressValue = value;
    [self setProgressValue:0.0];
    [_progressBar setIndeterminate:(value == 0.0)];
    [_progressBar startAnimation:self];
    [_progressBar setUsesThreadedAnimation:YES];
}


- (NSTouchBar *)makeTouchBar
{
    NSTouchBar *touchBar = [[NSTouchBar alloc] init];
    touchBar.defaultItemIdentifiers = @[ SUStatusControllerTouchBarIdentifier,];
    touchBar.principalItemIdentifier = SUStatusControllerTouchBarIdentifier;
    touchBar.delegate = self;
    return touchBar;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar * __unused)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
    if ([identifier isEqualToString:SUStatusControllerTouchBarIdentifier]) {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        SUTouchBarButtonGroup *group = [[SUTouchBarButtonGroup alloc] initByReferencingButtons:@[_actionButton,]];
        item.viewController = group;
        _touchBarButton = group.buttons.firstObject;
        [_touchBarButton bind:@"title" toObject:_actionButton withKeyPath:@"title" options:nil];
        [_touchBarButton bind:@"enabled" toObject:_actionButton withKeyPath:@"enabled" options:nil];
        return item;
    }
    return nil;
}

@end

#endif
