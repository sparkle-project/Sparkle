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

// Buffering parameters for -showWindow: and -closeWithCompletionBlock:. We hide
// the window entirely if a close arrives within SUStatusDisplayDelay,
// and we enforce a minimum visible duration of SUStatusMinimumDisplayTime
// once the window has actually appeared on screen.
static const NSTimeInterval SUStatusDisplayDelay = 0.3;
static const NSTimeInterval SUStatusMinimumDisplayTime = 0.7;

@interface SUStatusController () <NSTouchBarDelegate>

// These properties are used for bindings
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *buttonTitle;

@end

@implementation SUStatusController
{
    NSString *_windowTitle;
    NSValue *_centerPointValue;
    NSString *_title;
    NSString *_buttonTitle;
    SUHost *_host;
    NSButton *_touchBarButton;
    
    IBOutlet NSButton *_actionButton;
    IBOutlet NSTextField *_statusTextField;
    IBOutlet NSProgressIndicator *_progressBar;

    BOOL _waitingToShowWindow;
    NSTimeInterval _windowShownTime;
    void (^_pendingCloseCompletion)(BOOL userCancelled);
    
    BOOL _minimizable;
    BOOL _closable;
}

@synthesize title = _title;
@synthesize buttonTitle = _buttonTitle;
@synthesize progressValue = _progressValue;
@synthesize maxProgressValue = _maxProgressValue;
@synthesize statusText = _statusText;

- (instancetype)initWithHost:(SUHost *)aHost windowTitle:(NSString *)windowTitle centerPointValue:(NSValue *)centerPointValue minimizable:(BOOL)minimizable closable:(BOOL)closable
{
    self = [super initWithWindowNibName:@"SUStatus" owner:self];
	if (self)
	{
        _host = aHost;
        _centerPointValue = centerPointValue;
        _minimizable = minimizable;
        _closable = closable;
        _windowTitle = [windowTitle copy];
        [self setShouldCascadeWindows:NO];
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ <%@>", [self class], _host.bundlePath];
}

- (void)windowDidLoad 
{
    NSWindow *window = self.window;
    NSRect windowFrame = window.frame;
    
    if (_centerPointValue != nil) {
        NSPoint centerPoint = _centerPointValue.pointValue;
        [window setFrameOrigin:NSMakePoint(centerPoint.x - windowFrame.size.width / 2.0, centerPoint.y - windowFrame.size.height / 2.0)];
    } else {
        [window center];
    }
    
    if (_minimizable) {
        window.styleMask = (NSWindowStyleMask)(window.styleMask | NSWindowStyleMaskMiniaturizable);
    }
    if (_closable) {
        window.styleMask = (NSWindowStyleMask)(window.styleMask | NSWindowStyleMaskClosable);
    }
    [_progressBar setUsesThreadedAnimation:YES];
    [_statusTextField setFont:[NSFont monospacedDigitSystemFontOfSize:0 weight:NSFontWeightRegular]];
    
    if (@available(macOS 26, *)) {
        _actionButton.controlSize = NSControlSizeLarge;
    }
    
    window.title = _windowTitle;
}

- (NSImage *)applicationIcon
{
    return [SUApplicationInfo bestIconForHost:_host];
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

- (void)showWindow:(id)sender
{
    // If the window is already visible just call through for default handling
    if (self.window.visible) {
        [super showWindow:sender];
        return;
    }

    // Already scheduled - just keep waiting
    if (_waitingToShowWindow) {
        return;
    }

    _waitingToShowWindow = YES;

    __weak __typeof__(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SUStatusDisplayDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __typeof__(self) strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf->_waitingToShowWindow) {
            [strongSelf _reallyShowWindow:sender];
        }
    });
}

- (void)_reallyShowWindow:(id)sender SPU_OBJC_DIRECT
{
    _waitingToShowWindow = NO;
    _windowShownTime = [NSDate timeIntervalSinceReferenceDate];
    [super showWindow:sender];
}

- (void)closeWithCompletionBlock:(void (^)(BOOL userCancelled))completion
{
    // If the window isn't on screen, close silently and complete immediately.
    if (_waitingToShowWindow || !self.window.visible) {
        [self close];
        if (completion != nil) {
            completion(NO);
        }
        return;
    }

    NSTimeInterval elapsed = [NSDate timeIntervalSinceReferenceDate] - _windowShownTime;
    if (elapsed >= SUStatusMinimumDisplayTime) {
        [self close];
        if (completion != nil) {
            completion(NO);
        }
        return;
    }

    // Replace any previously pending close. (Not expected, but safe.)
    _pendingCloseCompletion = [completion copy];

    NSTimeInterval remaining = SUStatusMinimumDisplayTime - elapsed;
    __weak __typeof__(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(remaining * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __typeof__(self) strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        void (^pendingCompletion)(BOOL) = strongSelf->_pendingCloseCompletion;
        if (pendingCompletion == nil) {
            // -close was called externally; pending state was discarded.
            return;
        }
        strongSelf->_pendingCloseCompletion = nil;
        [strongSelf close];
        pendingCompletion(NO);
    });
}

- (BOOL)closeImmediately
{
    void (^pending)(BOOL) = _pendingCloseCompletion;
    _pendingCloseCompletion = nil;
    [self close];
    if (pending == nil) {
        return NO;
    }
    pending(YES);
    return YES;
}

- (void)close
{
    // -close is the abort path: silently discard any pending buffered
    // presentation or deferred close. Callers driving the buffered API use
    // -closeWithCompletionBlock: instead, which gates the
    // window's actual disappearance behind the minimum display time.
    _waitingToShowWindow = NO;
    _windowShownTime = 0;
    _pendingCloseCompletion = nil;
    [super close];
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
