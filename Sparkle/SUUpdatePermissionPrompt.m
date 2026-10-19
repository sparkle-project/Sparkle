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
    IBOutlet NSView *_responseView;
    IBOutlet NSStackView *_responseButtonsStackView;
    IBOutlet NSView *_infoChoiceView;
    IBOutlet NSView *_automaticallyDownloadUpdatesView;
    IBOutlet NSButton *_cancelButton;
    IBOutlet NSButton *_checkButton;
    IBOutlet NSTextField *_checkForUpdatesAutomaticallyTextField;
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

    // The disclosed profile info is kept outside of the stack view in the nib, otherwise it would
    // cover the rest of the dialog in Interface Builder. Insert it above the response buttons.
    NSUInteger disclosureIndex = [_stackView.arrangedSubviews indexOfObject:_responseView];
    if (disclosureIndex != NSNotFound) {
        [_stackView insertArrangedSubview:_placeholderView atIndex:(NSInteger)disclosureIndex];
        [_stackView insertArrangedSubview:_moreInfoView atIndex:(NSInteger)disclosureIndex + 1];
    }

    for (NSView *disclosedView in @[_placeholderView, _moreInfoView]) {
        [disclosedView.widthAnchor constraintEqualToAnchor:_stackView.widthAnchor].active = YES;
    }

    // Give the question and the choices below it better grouping
    [_stackView setCustomSpacing:SUUpdatePermissionPromptGroupElementSpacing afterView:_promptView];

#if SPARKLE_COPY_LOCALIZATIONS
    NSBundle *sparkleBundle = SUSparkleBundle();
#endif

    // Keep hidden window title for accessibility
    window.title = SULocalizedStringFromTableInBundle(@"Software Update", SPARKLE_TABLE, sparkleBundle, nil);
    window.titleVisibility = NSWindowTitleHidden;
    
    // Fix to make sure buttons are on right side, aligned correctly, and pointing correct direction
    // in RTL languages like Hebrew and Arabic
    for (NSButton *checkbox in @[_automaticallyDownloadAndInstallUpdatesButton, _includeAnonymousSystemProfileButton]) {
        checkbox.userInterfaceLayoutDirection = _stackView.userInterfaceLayoutDirection;
        checkbox.imagePosition = NSImageLeading;
        checkbox.alignment = NSTextAlignmentNatural;
    }
    _anonymousInfoDisclosureButton.userInterfaceLayoutDirection = _stackView.userInterfaceLayoutDirection;

    _cancelButton.controlSize = NSControlSizeLarge;
    _checkButton.controlSize = NSControlSizeLarge;

    if (@available(macOS 26, *)) {
    } else {
        // Alerts center their icon before macOS 26
        _applicationIconLeadingLayoutConstraint.active = NO;
        [_applicationIconImageView.centerXAnchor constraintEqualToAnchor:_promptView.centerXAnchor].active = YES;
    }

    _checkButton.title = SULocalizedStringFromTableInBundle(@"Check Automatically", SPARKLE_TABLE, sparkleBundle, nil);
    _cancelButton.title = SULocalizedStringFromTableInBundle(@"Don’t Check", SPARKLE_TABLE, sparkleBundle, nil);
    _checkForUpdatesAutomaticallyTextField.stringValue = SULocalizedStringFromTableInBundle(@"Check for updates automatically?", SPARKLE_TABLE, sparkleBundle, nil);
    _includeAnonymousSystemProfileButton.title = SULocalizedStringFromTableInBundle(@"Include anonymous system profile", SPARKLE_TABLE, sparkleBundle, nil);
    _automaticallyDownloadAndInstallUpdatesButton.title = SULocalizedStringFromTableInBundle(@"Automatically download and install updates", SPARKLE_TABLE, sparkleBundle, nil);
    _anonymousSystemProfileDisclosureInformation.stringValue = SULocalizedStringFromTableInBundle(@"Anonymous system profile information is used to help us plan future development work. Please contact us if you have any questions about this.\n\nThis is the information that would be sent:", SPARKLE_TABLE, sparkleBundle, nil);

    [window center];
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
