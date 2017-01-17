//
//  SUUpdatePermissionPrompt.m
//  Sparkle
//
//  Created by Andy Matuschak on 1/24/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUpdatePermissionPrompt.h"
#import "SUUpdatePermissionResponse.h"

#import "SUHost.h"
#import "SUConstants.h"
#import "SULocalizations.h"
#import "SUApplicationInfo.h"
#import "SUTouchBarForwardDeclarations.h"
#import "SUTouchBarButtonGroup.h"

static NSString *const SUUpdatePermissionPromptTouchBarIndentifier = @"" SPARKLE_BUNDLE_IDENTIFIER ".SUUpdatePermissionPrompt";

@interface SUUpdatePermissionPrompt () <NSTouchBarDelegate>

@property (assign) BOOL isShowingMoreInfo;
@property (assign) BOOL shouldSendProfile;

@property (strong) SUHost *host;
@property (strong) NSArray *systemProfileInformationArray;
@property (weak) IBOutlet NSTextField *descriptionTextField;
@property (weak) IBOutlet NSView *moreInfoView;
@property (weak) IBOutlet NSButton *moreInfoButton;
@property (weak) IBOutlet NSTableView *profileTableView;
@property (weak) IBOutlet NSButton *cancelButton;
@property (weak) IBOutlet NSButton *checkButton;

@property (nonatomic, readonly) void (^reply)(SUUpdatePermissionResponse *);

@end

@implementation SUUpdatePermissionPrompt

@synthesize reply = _reply;
@synthesize isShowingMoreInfo = _isShowingMoreInfo;
@synthesize shouldSendProfile = _shouldSendProfile;
@synthesize host;
@synthesize systemProfileInformationArray;
@synthesize descriptionTextField;
@synthesize moreInfoView;
@synthesize moreInfoButton;
@synthesize profileTableView;
@synthesize cancelButton;
@synthesize checkButton;

- (BOOL)shouldAskAboutProfile
{
    return [[self.host objectForInfoDictionaryKey:SUEnableSystemProfilingKey] boolValue];
}

- (instancetype)initWithHost:(SUHost *)aHost systemProfile:(NSArray *)profile reply:(void (^)(SUUpdatePermissionResponse *))reply
{
    self = [super initWithWindowNibName:@"SUUpdatePermissionPrompt"];
	if (self)
	{
        _reply = reply;
        host = aHost;
        self.isShowingMoreInfo = NO;
        self.shouldSendProfile = [self shouldAskAboutProfile];
        systemProfileInformationArray = profile;
        [self setShouldCascadeWindows:NO];
    }
    return self;
}

+ (void)promptWithHost:(SUHost *)host systemProfile:(NSArray *)profile reply:(void (^)(SUUpdatePermissionResponse *))reply
{
    // If this is a background application we need to focus it in order to bring the prompt
    // to the user's attention. Otherwise the prompt would be hidden behind other applications and
    // the user would not know why the application was paused.
	if ([SUApplicationInfo isBackgroundApplication:[NSApplication sharedApplication]]) {
        [[NSApplication sharedApplication] activateIgnoringOtherApps:YES];
    }

    if (![NSApp modalWindow]) { // do not prompt if there is is another modal window on screen
        SUUpdatePermissionPrompt *prompt = [[[self class] alloc] initWithHost:host systemProfile:profile reply:reply];
        NSWindow *window = [prompt window];
        if (window) {
            [NSApp runModalForWindow:window];
        }
    }
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], [self.host bundlePath]]; }

- (void)windowDidLoad
{
	if (![self shouldAskAboutProfile])
	{
        NSRect frame = [[self window] frame];
        frame.size.height -= [self.moreInfoButton frame].size.height;
        [[self window] setFrame:frame display:YES];
    } else {
        // Set the table view's delegate so we can disable row selection.
        [self.profileTableView setDelegate:(id)self];
    }
}

- (BOOL)tableView:(NSTableView *) __unused tableView shouldSelectRow:(NSInteger) __unused row { return NO; }


- (NSImage *)icon
{
    return [SUApplicationInfo bestIconForHost:self.host];
}

- (NSString *)promptDescription
{
    return [NSString stringWithFormat:SULocalizedString(@"Should %1$@ automatically check for updates? You can always check for updates manually from the %1$@ menu.", nil), [self.host name]];
}

- (IBAction)toggleMoreInfo:(id)__unused sender
{
    self.isShowingMoreInfo = !self.isShowingMoreInfo;

    NSView *contentView = [[self window] contentView];
    NSRect contentViewFrame = [contentView frame];
    NSRect windowFrame = [[self window] frame];

    NSRect profileMoreInfoViewFrame = [self.moreInfoView frame];
    NSRect profileMoreInfoButtonFrame = [self.moreInfoButton frame];
    NSRect descriptionFrame = [self.descriptionTextField frame];

	if (self.isShowingMoreInfo)
	{
        // Add the subview
        contentViewFrame.size.height += profileMoreInfoViewFrame.size.height;
        profileMoreInfoViewFrame.origin.y = profileMoreInfoButtonFrame.origin.y - profileMoreInfoViewFrame.size.height;
        profileMoreInfoViewFrame.origin.x = descriptionFrame.origin.x;
        profileMoreInfoViewFrame.size.width = descriptionFrame.size.width;

        windowFrame.size.height += profileMoreInfoViewFrame.size.height;
        windowFrame.origin.y -= profileMoreInfoViewFrame.size.height;

        [self.moreInfoView setFrame:profileMoreInfoViewFrame];
        [self.moreInfoView setHidden:YES];
        [contentView addSubview:self.moreInfoView
                     positioned:NSWindowBelow
                     relativeTo:self.moreInfoButton];
    } else {
        // Remove the subview
        [self.moreInfoView setHidden:NO];
        [self.moreInfoView removeFromSuperview];
        contentViewFrame.size.height -= profileMoreInfoViewFrame.size.height;

        windowFrame.size.height -= profileMoreInfoViewFrame.size.height;
        windowFrame.origin.y += profileMoreInfoViewFrame.size.height;
    }
    [[self window] setFrame:windowFrame display:YES animate:YES];
    [contentView setFrame:contentViewFrame];
    [contentView setNeedsDisplay:YES];
    [self.moreInfoView setHidden:!self.isShowingMoreInfo];
}

- (IBAction)finishPrompt:(id)sender
{
    SUUpdatePermissionResponse *response = [[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:([sender tag] == 1) sendSystemProfile:self.shouldSendProfile];
    self.reply(response);
    
    [[self window] close];
    [NSApp stopModal];
}

- (NSTouchBar *)makeTouchBar
{
    NSTouchBar *touchBar = [[NSClassFromString(@"NSTouchBar") alloc] init];
    touchBar.defaultItemIdentifiers = @[SUUpdatePermissionPromptTouchBarIndentifier,];
    touchBar.principalItemIdentifier = SUUpdatePermissionPromptTouchBarIndentifier;
    touchBar.delegate = self;
    return touchBar;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar * __unused)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
    if ([identifier isEqualToString:SUUpdatePermissionPromptTouchBarIndentifier]) {
        NSCustomTouchBarItem* item = [(NSCustomTouchBarItem *)[NSClassFromString(@"NSCustomTouchBarItem") alloc] initWithIdentifier:identifier];
        item.viewController = [[SUTouchBarButtonGroup alloc] initByReferencingButtons:@[self.checkButton, self.cancelButton]];
        return item;
    }
    return nil;
}

@end
