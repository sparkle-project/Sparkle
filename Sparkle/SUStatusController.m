//
//  SUStatusController.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/14/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUOperatingSystem.h"
#import "SUStatusController.h"
#import "SUHost.h"
#import "SULocalizations.h"
#import "SUApplicationInfo.h"
#import "SUTouchBarForwardDeclarations.h"
#import "SUTouchBarButtonGroup.h"

static NSString *const SUStatusControllerTouchBarIndentifier = @"" SPARKLE_BUNDLE_IDENTIFIER ".SUStatusController";

@interface SUStatusController () <NSTouchBarDelegate>
@property (copy) NSString *title, *buttonTitle;
@property (strong) SUHost *host;
@property NSButton *touchBarButton;
@end

@implementation SUStatusController
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

- (instancetype)initWithHost:(SUHost *)aHost
{
    self = [super initWithWindowNibName:@"SUStatus"];
	if (self)
	{
        self.host = aHost;
        [self setShouldCascadeWindows:NO];
    }
    return self;
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], [self.host bundlePath]]; }

- (void)windowDidLoad
{
    if ([SUApplicationInfo isBackgroundApplication:[NSApplication sharedApplication]]) {
        [[self window] setLevel:NSFloatingWindowLevel];
    }

    [[self window] center];
    [[self window] setFrameAutosaveName:@"SUStatusFrame"];
    [self.progressBar setUsesThreadedAnimation:YES];

    if ([SUOperatingSystem isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){10, 11, 0}]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        [self.statusTextField setFont:[NSFont monospacedDigitSystemFontOfSize:0 weight:NSFontWeightRegular]];
#pragma clang diagnostic pop
    }
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
    NSTouchBar *touchBar = [[NSClassFromString(@"NSTouchBar") alloc] init];
    touchBar.defaultItemIdentifiers = @[ SUStatusControllerTouchBarIndentifier,];
    touchBar.principalItemIdentifier = SUStatusControllerTouchBarIndentifier;
    touchBar.delegate = self;
    return touchBar;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar * __unused)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
    if ([identifier isEqualToString:SUStatusControllerTouchBarIndentifier]) {
        NSCustomTouchBarItem *item = [(NSCustomTouchBarItem *)[NSClassFromString(@"NSCustomTouchBarItem") alloc] initWithIdentifier:identifier];
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
