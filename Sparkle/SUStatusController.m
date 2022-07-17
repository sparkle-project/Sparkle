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
#import "SUOperatingSystem.h"
#import "SUTouchBarButtonGroup.h"

static NSString *const SUStatusControllerTouchBarIndentifier = @"" SPARKLE_BUNDLE_IDENTIFIER ".SUStatusController";

@interface SUStatusController () <NSTouchBarDelegate>
@property (copy) NSString *title, *buttonTitle;
@property (strong) SUHost *host;
@property NSButton *touchBarButton;
@property (nonatomic, readonly) BOOL minimizable;
@end

@implementation SUStatusController
{
    NSValue *_centerPointValue;
    BOOL _closable;
}

@synthesize progressValue;
@synthesize maxProgressValue;
@synthesize statusText;
@synthesize title;
@synthesize buttonTitle;
@synthesize host;
@synthesize actionButton;
@synthesize progressBar;
@synthesize statusTextField;
@synthesize touchBarButton;
@synthesize minimizable = _minimizable;

- (instancetype)initWithHost:(SUHost *)aHost centerPointValue:(NSValue *)centerPointValue minimizable:(BOOL)minimizable closable:(BOOL)closable
{
    self = [super initWithWindowNibName:@"SUStatus" owner:self];
	if (self)
	{
        self.host = aHost;
        _centerPointValue = centerPointValue;
        _minimizable = minimizable;
        _closable = closable;
        [self setShouldCascadeWindows:NO];
    }
    return self;
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], [self.host bundlePath]]; }

- (void)windowDidLoad
{
    NSRect windowFrame = self.window.frame;
    
    if (_centerPointValue != nil) {
        NSPoint centerPoint = _centerPointValue.pointValue;
        [self.window setFrameOrigin:NSMakePoint(centerPoint.x - windowFrame.size.width / 2.0, centerPoint.y - windowFrame.size.height / 2.0)];
    } else {
        [self.window center];
    }
    
    if (self.minimizable) {
        self.window.styleMask |= NSWindowStyleMaskMiniaturizable;
    }
    if (_closable) {
        self.window.styleMask |= NSWindowStyleMaskClosable;
    }
    [self.progressBar setUsesThreadedAnimation:YES];
    [self.statusTextField setFont:[NSFont monospacedDigitSystemFontOfSize:0 weight:NSFontWeightRegular]];
}

- (NSString *)windowTitle
{
    return [NSString stringWithFormat:SULocalizedString(@"Updating %@", nil), [self.host name]];
}

- (NSImage *)applicationIcon
{
    return [SUApplicationInfo bestIconForHost:self.host];
}

- (void)beginActionWithTitle:(NSString *)aTitle maxProgressValue:(double)aMaxProgressValue statusText:(NSString *)aStatusText
{
    self.title = aTitle;

    self.maxProgressValue = aMaxProgressValue;
    self.statusText = aStatusText;
}

- (void)setButtonTitle:(NSString *)aButtonTitle target:(id)target action:(SEL)action isDefault:(BOOL)isDefault
{
    self.buttonTitle = aButtonTitle;

    [self window];
    [self.actionButton sizeToFit];
    // Except we're going to add 15 px for padding.
    [self.actionButton setFrameSize:NSMakeSize([self.actionButton frame].size.width + 15, [self.actionButton frame].size.height)];
    // Now we have to move it over so that it's always 15px from the side of the window.
    [self.actionButton setFrameOrigin:NSMakePoint([[self window] frame].size.width - 15 - [self.actionButton frame].size.width, [self.actionButton frame].origin.y)];
    // Redisplay superview to clean up artifacts
    [[self.actionButton superview] display];

    [self.actionButton setTarget:target];
    [self.actionButton setAction:action];
    [self.actionButton setKeyEquivalent:isDefault ? @"\r" : @""];
    
    self.touchBarButton.target = self.actionButton.target;
    self.touchBarButton.action = self.actionButton.action;
    self.touchBarButton.keyEquivalent = self.actionButton.keyEquivalent;

    // 06/05/2008 Alex: Avoid a crash when cancelling during the extraction
    [self setButtonEnabled:(target != nil)];
}

- (BOOL)progressBarShouldAnimate
{
    return YES;
}

- (void)setButtonEnabled:(BOOL)enabled
{
    [self.actionButton setEnabled:enabled];
}

- (BOOL)isButtonEnabled
{
    return [self.actionButton isEnabled];
}

- (void)setMaxProgressValue:(double)value
{
	if (value < 0.0) value = 0.0;
    maxProgressValue = value;
    [self setProgressValue:0.0];
    [self.progressBar setIndeterminate:(value == 0.0)];
    [self.progressBar startAnimation:self];
    [self.progressBar setUsesThreadedAnimation:YES];
}


- (NSTouchBar *)makeTouchBar
{
    NSTouchBar *touchBar = [[NSTouchBar alloc] init];
    touchBar.defaultItemIdentifiers = @[ SUStatusControllerTouchBarIndentifier,];
    touchBar.principalItemIdentifier = SUStatusControllerTouchBarIndentifier;
    touchBar.delegate = self;
    return touchBar;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar * __unused)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
    if ([identifier isEqualToString:SUStatusControllerTouchBarIndentifier]) {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        SUTouchBarButtonGroup *group = [[SUTouchBarButtonGroup alloc] initByReferencingButtons:@[self.actionButton,]];
        item.viewController = group;
        self.touchBarButton = group.buttons.firstObject;
        [self.touchBarButton bind:@"title" toObject:self.actionButton withKeyPath:@"title" options:nil];
        [self.touchBarButton bind:@"enabled" toObject:self.actionButton withKeyPath:@"enabled" options:nil];
        return item;
    }
    return nil;
}

@end

#endif
