//
//  SUUpdatePermissionPrompt.m
//  Sparkle
//
//  Created by Andy Matuschak on 1/24/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import "SUUpdatePermissionPrompt.h"
#import "SPUUpdatePermissionRequest.h"
#import "SUUpdatePermissionResponse.h"
#import "SULocalizations.h"

#import "SUHost.h"
#import "SUConstants.h"
#import "SUApplicationInfo.h"
#import "SUTouchBarButtonGroup.h"

static NSString *const SUUpdatePermissionPromptTouchBarIdentifier = @"" SPARKLE_BUNDLE_IDENTIFIER ".SUUpdatePermissionPrompt";

static const CGFloat SUUpdatePermissionPromptGroupElementSpacing = 12.0;

@interface SUUpdatePermissionPrompt () <NSTouchBarDelegate>

// These properties are used for bindings
@property (nonatomic, readonly) NSArray *systemProfileInformationArray;
@property (nonatomic) BOOL shouldSendProfile;
@property (nonatomic) BOOL automaticallyDownloadUpdates;

@end

@implementation SUUpdatePermissionPrompt
{
    SUHost *_host;
    
    IBOutlet NSStackView *_stackView;
    IBOutlet NSView *_promptView;
    IBOutlet NSImageView *_applicationIconImageView;
    IBOutlet NSLayoutConstraint *_applicationIconLeadingLayoutConstraint;
    IBOutlet NSView *_moreInfoView;
    IBOutlet NSView *_placeholderView;
    IBOutlet NSView *_infoChoiceView;
    IBOutlet NSView *_automaticallyDownloadUpdatesView;
    IBOutlet NSButton *_cancelButton;
    IBOutlet NSButton *_checkButton;
    IBOutlet NSTextField *_checkForUpdatesAutomaticallyTextField;
    IBOutlet NSTextField *_promptDescriptionTextField;
    IBOutlet NSButton *_includeAnonymousSystemProfileButton;
    IBOutlet NSButton *_anonymousInfoDisclosureButton;
    IBOutlet NSButton *_automaticallyDownloadAndInstallUpdatesButton;
    IBOutlet NSTextField *_anonymousSystemProfileDisclosureInformation;
    IBOutlet NSLayoutConstraint *_placeholderHeightLayoutConstraint;
    
    void (^_reply)(SUUpdatePermissionResponse *);
}

@synthesize shouldSendProfile = _shouldSendProfile;
@synthesize automaticallyDownloadUpdates = _automaticallyDownloadUpdates;
@synthesize systemProfileInformationArray = _systemProfileInformationArray;

- (instancetype)initPromptWithHost:(SUHost *)theHost request:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply
{
    self = [super initWithWindowNibName:@"SUUpdatePermissionPrompt"];
    if (self)
    {
        _reply = [reply copy];
        _host = theHost;
        _shouldSendProfile = [self shouldAskAboutProfile];
        _systemProfileInformationArray = request.systemProfile;
        _automaticallyDownloadUpdates = [theHost boolForKey:SUAutomaticallyUpdateKey];
        [self setShouldCascadeWindows:NO];
    } else {
        assert(false);
    }
    return self;
}

- (BOOL)shouldAskAboutProfile
{
    return [_host boolForInfoDictionaryKey:SUEnableSystemProfilingKey];
}

- (BOOL)allowsAutomaticUpdates
{
    NSNumber *allowsAutomaticUpdates = [_host boolNumberForInfoDictionaryKey:SUAllowsAutomaticUpdatesKey];
    return (allowsAutomaticUpdates == nil || allowsAutomaticUpdates.boolValue);
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], _host.bundlePath]; }

- (void)windowDidLoad
{
    NSWindow *window = self.window;

    window.movableByWindowBackground = YES;

    _infoChoiceView.hidden = ![self shouldAskAboutProfile];
    _automaticallyDownloadUpdatesView.hidden = ![self allowsAutomaticUpdates];

    // Give the question and the choices below it better grouping
    [_stackView setCustomSpacing:SUUpdatePermissionPromptGroupElementSpacing afterView:_promptView];

#if SPARKLE_COPY_LOCALIZATIONS
    NSBundle *sparkleBundle = SUSparkleBundle();
#endif

    // Keep hidden window title for accessibility
    window.title = SULocalizedStringFromTableInBundle(@"Software Update", SPARKLE_TABLE, sparkleBundle, nil);
    window.titleVisibility = NSWindowTitleHidden;

    // The dialog has a fixed width, so let long localized checkbox titles wrap instead of being
    // truncated. Note button cells only wrap when their width is constrained, which it is here.
    for (NSButton *checkbox in @[_automaticallyDownloadAndInstallUpdatesButton, _includeAnonymousSystemProfileButton]) {
        NSCell *cell = checkbox.cell;
        cell.usesSingleLineMode = NO;
        cell.lineBreakMode = NSLineBreakByWordWrapping;
        cell.wraps = YES;
    }

    if (@available(macOS 26, *)) {
        _cancelButton.controlSize = NSControlSizeLarge;
        _checkButton.controlSize = NSControlSizeLarge;
    } else {
        // Alerts center their icon and text before macOS 26
        _applicationIconLeadingLayoutConstraint.active = NO;
        [_applicationIconImageView.centerXAnchor constraintEqualToAnchor:_promptView.centerXAnchor].active = YES;

        _checkForUpdatesAutomaticallyTextField.alignment = NSTextAlignmentCenter;
        _promptDescriptionTextField.alignment = NSTextAlignmentCenter;
    }

    _checkButton.title = SULocalizedStringFromTableInBundle(@"Check Automatically", SPARKLE_TABLE, sparkleBundle, nil);
    _cancelButton.title = SULocalizedStringFromTableInBundle(@"Don’t Check", SPARKLE_TABLE, sparkleBundle, nil);
    _checkForUpdatesAutomaticallyTextField.stringValue = SULocalizedStringFromTableInBundle(@"Check for updates automatically?", SPARKLE_TABLE, sparkleBundle, nil);
    _includeAnonymousSystemProfileButton.title = SULocalizedStringFromTableInBundle(@"Include anonymous system profile", SPARKLE_TABLE, sparkleBundle, nil);
    _automaticallyDownloadAndInstallUpdatesButton.title = SULocalizedStringFromTableInBundle(@"Automatically download and install updates", SPARKLE_TABLE, sparkleBundle, nil);
    _anonymousSystemProfileDisclosureInformation.stringValue = SULocalizedStringFromTableInBundle(@"Anonymous system profile information is used to help us plan future development work. Please contact us if you have any questions about this.\n\nThis is the information that would be sent:", SPARKLE_TABLE, sparkleBundle, nil);

    // Wrapping labels can only compute the right height once they know their final width. The width
    // stored in the nib is a design time estimate, so let them adopt the width they ended up with.
    [window layoutIfNeeded];

    for (NSTextField *label in @[_checkForUpdatesAutomaticallyTextField, _promptDescriptionTextField, _anonymousSystemProfileDisclosureInformation]) {
        label.preferredMaxLayoutWidth = NSWidth(label.frame);
    }

    [window layoutIfNeeded];

    [self _embedContentInGlassBackgroundForWindow:window];

    [window center];
}

// Draw the dialog on a glass background with the corner radius of a system prompt. AppKit has no
// API for the corner radius of a window, so the rounded background is drawn by a glass effect view
// inside the window while the window itself stops drawing.
//
// Clipping the glass view is what makes the corners work, without it the content is drawn as a
// rectangle over the rounded glass. The window keeps its title bar style mask so that it can still
// become the key window, which also means no window subclass is needed. Before macOS 26 the dialog
// stays a regular window.
- (void)_embedContentInGlassBackgroundForWindow:(NSWindow *)window
{
    if (@available(macOS 26, *)) {
        // AppKit does not expose the corner radius of a window, and the layout regions only report
        // content insets rather than corner geometry. This value is measured off a system prompt:
        // fitting its edge profile against a circle gives 52 pixels at 2x on every sample point.
        static const CGFloat glassCornerRadius = 26.0;

        NSView *contentView = window.contentView;

        NSGlassEffectView *glassView = [[NSGlassEffectView alloc] initWithFrame:contentView.frame];
        glassView.cornerRadius = glassCornerRadius;
        glassView.style = NSGlassEffectViewStyleRegular;
        glassView.clipsToBounds = YES;

        window.contentView = glassView;

        contentView.frame = glassView.bounds;
        contentView.autoresizingMask = (NSAutoresizingMaskOptions)(NSViewWidthSizable | NSViewHeightSizable);
        glassView.contentView = contentView;

        window.backgroundColor = NSColor.clearColor;
        window.opaque = NO;

        [window invalidateShadow];
    }
}

- (BOOL)tableView:(NSTableView *) __unused tableView shouldSelectRow:(NSInteger) __unused row { return NO; }


- (NSImage *)icon
{
    return [SUApplicationInfo bestIconForHost:_host];
}

- (NSString *)promptDescription
{
    return [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"Should %1$@ automatically check for updates? You can always check for updates manually from the %1$@ menu.", SPARKLE_TABLE, SUSparkleBundle(), nil), _host.name];
}

- (IBAction)toggleMoreInfo:(id)__unused sender
{
    // Use a placeholder view to unhide/hide before putting the more info view in place
    // This allows us to animate resizing the more info view in place more easily
    
    static const CGFloat TOGGLE_INFO_ANIMATION_DURATION = 0.2;
    
    BOOL disclosingInfo = (_anonymousInfoDisclosureButton.state == NSControlStateValueOn);
    
    if (disclosingInfo) {
        _placeholderHeightLayoutConstraint.constant = 0.0;
        _placeholderView.hidden = NO;
        
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
            context.duration = TOGGLE_INFO_ANIMATION_DURATION;
            
            self->_placeholderHeightLayoutConstraint.animator.constant = _moreInfoView.frame.size.height;
        } completionHandler:^{
            self->_placeholderView.hidden = YES;
            self->_moreInfoView.hidden = NO;
        }];
    } else {
        _placeholderHeightLayoutConstraint.constant = _moreInfoView.frame.size.height;
        _moreInfoView.hidden = YES;
        _placeholderView.hidden = NO;
        
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
            context.duration = TOGGLE_INFO_ANIMATION_DURATION;
            
            self->_placeholderHeightLayoutConstraint.animator.constant = 0.0;
        } completionHandler:^{
            self->_placeholderView.hidden = YES;
        }];
    }
}

- (IBAction)finishPrompt:(NSButton *)sender
{
    BOOL automaticUpdateChecksEnabled = ([sender tag] == 1);
    
    NSNumber *automaticUpdateDownloading;
    if ([self allowsAutomaticUpdates]) {
        automaticUpdateDownloading = @(automaticUpdateChecksEnabled && _automaticallyDownloadUpdates);
    } else {
        automaticUpdateDownloading = nil;
    }
    
    SUUpdatePermissionResponse *response = [[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:automaticUpdateChecksEnabled automaticUpdateDownloading:automaticUpdateDownloading sendSystemProfile:_shouldSendProfile];
    _reply(response);
    
    [self close];
}

- (NSTouchBar *)makeTouchBar
{
    NSTouchBar *touchBar = [[NSTouchBar alloc] init];
    touchBar.defaultItemIdentifiers = @[SUUpdatePermissionPromptTouchBarIdentifier,];
    touchBar.principalItemIdentifier = SUUpdatePermissionPromptTouchBarIdentifier;
    touchBar.delegate = self;
    return touchBar;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar * __unused)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
    if ([identifier isEqualToString:SUUpdatePermissionPromptTouchBarIdentifier]) {
        NSCustomTouchBarItem* item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        item.viewController = [[SUTouchBarButtonGroup alloc] initByReferencingButtons:@[_checkButton, _cancelButton]];
        return item;
    }
    return nil;
}

@end

#endif
