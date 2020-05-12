//
//  SUUpdateAlert.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

// -----------------------------------------------------------------------------
//	Headers:
// -----------------------------------------------------------------------------

#import "SUUpdateAlert.h"

#import "SUHost.h"
#import <WebKit/WebKit.h>

#import "SUConstants.h"
#import "SULog.h"
#import "SULocalizations.h"
#import "SUAppcastItem.h"
#import "SUApplicationInfo.h"
#import "SUSystemUpdateInfo.h"
#import "SUOperatingSystem.h"
#import "SUTouchBarForwardDeclarations.h"
#import "SUTouchBarButtonGroup.h"

static NSString *const SUUpdateAlertTouchBarIndentifier = @"" SPARKLE_BUNDLE_IDENTIFIER ".SUUpdateAlert";

// WebKit protocols are not explicitly declared until 10.11 SDK, so
// declare dummy protocols to keep the build working on earlier SDKs.
#if __MAC_OS_X_VERSION_MAX_ALLOWED < 101100
@protocol WebFrameLoadDelegate <NSObject>
@end
@protocol WebPolicyDelegate <NSObject>
@end
@protocol WebUIDelegate <NSObject>
@end
#endif

@interface SUUpdateAlert () <WebFrameLoadDelegate, WebPolicyDelegate, WebUIDelegate, NSTouchBarDelegate>

@property (strong) SUAppcastItem *updateItem;
@property (strong) SUHost *host;
@property (strong) void(^completionBlock)(SUUpdateAlertChoice);

@property (strong) NSProgressIndicator *releaseNotesSpinner;
@property (assign) BOOL webViewFinishedLoading;
@property (assign) BOOL observingAppearance;

@property (weak) IBOutlet WebView *releaseNotesView;
@property (weak) IBOutlet NSView *releaseNotesContainerView;
@property (weak) IBOutlet NSTextField *descriptionField;
@property (weak) IBOutlet NSButton *automaticallyInstallUpdatesButton;
@property (weak) IBOutlet NSButton *installButton;
@property (weak) IBOutlet NSButton *skipButton;
@property (weak) IBOutlet NSButton *laterButton;

@end

@implementation SUUpdateAlert

@synthesize completionBlock;
@synthesize versionDisplayer;

@synthesize updateItem;
@synthesize host;

@synthesize releaseNotesSpinner;
@synthesize webViewFinishedLoading;
@synthesize observingAppearance;

@synthesize releaseNotesView;
@synthesize releaseNotesContainerView;
@synthesize descriptionField;
@synthesize automaticallyInstallUpdatesButton;
@synthesize installButton;
@synthesize skipButton;
@synthesize laterButton;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item host:(SUHost *)aHost completionBlock:(void (^)(SUUpdateAlertChoice))block
{
    self = [super initWithWindowNibName:@"SUUpdateAlert"];
	if (self)
	{
        self.completionBlock = block;
        host = aHost;
        updateItem = item;
        [self setShouldCascadeWindows:NO];

        // Alex: This dummy line makes sure that the binary is linked against WebKit.
        // The SUUpdateAlert.xib file contains a WebView and if we don't link against WebKit,
        // we will get a runtime crash when decoding the NIB. It is better to get a link error.
        [WebView MIMETypesShownAsHTML];
    }
    return self;
}

- (void)dealloc {
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101400
    if (SUAVAILABLE(10, 14)) {
        if (self.observingAppearance) {
            [self.window removeObserver:self forKeyPath:@"effectiveAppearance"];
            self.observingAppearance = NO;
        }
    }
#endif
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(__attribute__((unused)) NSDictionary<NSKeyValueChangeKey,id> *)change context:(__attribute__((unused)) void *)context {
    if (object == self.window && [keyPath isEqualToString:@"effectiveAppearance"]) {
        [self adaptReleaseNotesAppearance];
    }
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], [self.host bundlePath]]; }

- (void)disableKeyboardShortcutForInstallButton {
    self.installButton.keyEquivalent = @"";
}

- (void)endWithSelection:(SUUpdateAlertChoice)choice
{
    [self.releaseNotesView stopLoading:self];
    self.releaseNotesView.frameLoadDelegate = nil;
    self.releaseNotesView.policyDelegate = nil;
    self.releaseNotesView.UIDelegate = nil;
    [self.releaseNotesView removeFromSuperview]; // Otherwise it gets sent Esc presses (why?!) and gets very confused.
    [self close];
    self.completionBlock(choice);
    self.completionBlock = nil;
}

- (IBAction)installUpdate:(id)__unused sender
{
    [self endWithSelection:SUInstallUpdateChoice];
}

- (IBAction)openInfoURL:(id)__unused sender
{
    [self endWithSelection:SUOpenInfoURLChoice];
}

- (IBAction)skipThisVersion:(id)__unused sender
{
    [self endWithSelection:SUSkipThisVersionChoice];
}

- (IBAction)remindMeLater:(id)__unused sender
{
    [self endWithSelection:SURemindMeLaterChoice];
}

- (void)displayReleaseNotes
{
    self.releaseNotesView.preferencesIdentifier = SUBundleIdentifier;
    WebPreferences *prefs = [self.releaseNotesView preferences];
    prefs.plugInsEnabled = NO;
    prefs.javaEnabled = NO;
    prefs.javaScriptEnabled = [self.host boolForInfoDictionaryKey:SUEnableJavaScriptKey];
    self.releaseNotesView.frameLoadDelegate = self;
    self.releaseNotesView.policyDelegate = self;
    self.releaseNotesView.UIDelegate = self;
    
    // Set the default font
    // "-apple-system-font" is a reference to the system UI font. "-apple-system" is the new recommended token, but for backward compatibility we can't use it.
    prefs.standardFontFamily = @"-apple-system-font";
    prefs.defaultFontSize = (int)[NSFont systemFontSize];

#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101400
    if (SUAVAILABLE(10, 14))
    {
        NSBox *darkBackgroundView = [[NSBox alloc] initWithFrame:self.releaseNotesView.frame];
        darkBackgroundView.boxType = NSBoxCustom;
        darkBackgroundView.fillColor = [NSColor textBackgroundColor];
        darkBackgroundView.borderColor = [NSColor clearColor];
        // Using auto-resizing mask instead of contraints works well enough
        darkBackgroundView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self.releaseNotesView.superview addSubview:darkBackgroundView positioned:NSWindowBelow relativeTo:self.releaseNotesView];
        self.releaseNotesView.drawsBackground = NO;

        prefs.userStyleSheetLocation = [[NSBundle bundleForClass:[self class]] URLForResource:@"DarkAqua" withExtension:@"css"];
        if (!self.observingAppearance) {
            [self.window addObserver:self forKeyPath:@"effectiveAppearance" options:NSKeyValueObservingOptionInitial context:nil];
            self.observingAppearance = YES;
        }
    }
#endif
    // Stick a nice big spinner in the middle of the web view until the page is loaded.
    NSRect frame = [[self.releaseNotesView superview] frame];
    self.releaseNotesSpinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(NSMidX(frame) - 16, NSMidY(frame) - 16, 32, 32)];
    [self.releaseNotesSpinner setStyle:NSProgressIndicatorSpinningStyle];
    [self.releaseNotesSpinner startAnimation:self];
    self.webViewFinishedLoading = NO;
    [[self.releaseNotesView superview] addSubview:self.releaseNotesSpinner];

    // If there's a release notes URL, load it; otherwise, just stick the contents of the description into the web view.
	if ([self.updateItem releaseNotesURL])
	{
        [[self.releaseNotesView mainFrame] loadRequest:[NSURLRequest requestWithURL:[self.updateItem releaseNotesURL] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30]];
	}
	else
	{
        [[self.releaseNotesView mainFrame] loadHTMLString:[self.updateItem itemDescription] baseURL:nil];
    }
}

- (BOOL)showsReleaseNotes
{
    NSNumber *shouldShowReleaseNotes = [self.host objectForInfoDictionaryKey:SUShowReleaseNotesKey];
	if (shouldShowReleaseNotes == nil)
	{
        // Don't show release notes if RSS item contains no description and no release notes URL:
        return (([self.updateItem itemDescription] != nil
                 && [[[self.updateItem itemDescription] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0)
                || [self.updateItem releaseNotesURL] != nil);
	}
	else
        return [shouldShowReleaseNotes boolValue];
}

- (BOOL)allowsAutomaticUpdates
{
    return [SUSystemUpdateInfo systemAllowsAutomaticUpdatesForHost:self.host]
            && !self.updateItem.isInformationOnlyUpdate;
}

- (void)windowDidLoad
{
    BOOL showReleaseNotes = [self showsReleaseNotes];

    [self.window setFrameAutosaveName: showReleaseNotes ? @"SUUpdateAlert" : @"SUUpdateAlertSmall" ];

    if ([SUApplicationInfo isBackgroundApplication:[NSApplication sharedApplication]]) {
        [self.window setLevel:NSFloatingWindowLevel]; // This means the window will float over all other apps, if our app is switched out ?!
    }

    if (self.updateItem.isInformationOnlyUpdate) {
        [self.installButton setTitle:SULocalizedString(@"Learn More...", @"Alternate title for 'Install Update' button when there's no download in RSS feed.")];
        [self.installButton setAction:@selector(openInfoURL:)];
    }

    if (showReleaseNotes) {
        [self displayReleaseNotes];
    } else {
        NSLayoutConstraint *automaticallyInstallUpdatesButtonToDescriptionFieldConstraint = [NSLayoutConstraint constraintWithItem:self.automaticallyInstallUpdatesButton attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.descriptionField attribute:NSLayoutAttributeBottom multiplier:1.0 constant:8.0];
        
        [self.window.contentView addConstraint:automaticallyInstallUpdatesButtonToDescriptionFieldConstraint];
        
        [self.releaseNotesContainerView removeFromSuperview];
    }
    
    // When we show release notes, it looks ugly if the install buttons are not closer to the release notes view
    // However when we don't show release notes, it looks ugly if the install buttons are too close to the description field. Shrugs.
    if (showReleaseNotes && ![self allowsAutomaticUpdates]) {
        NSLayoutConstraint *skipButtonToReleaseNotesContainerConstraint = [NSLayoutConstraint constraintWithItem:self.skipButton attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.releaseNotesContainerView attribute:NSLayoutAttributeBottom multiplier:1.0 constant:12.0];
        
        [self.window.contentView addConstraint:skipButtonToReleaseNotesContainerConstraint];
        
        [self.automaticallyInstallUpdatesButton removeFromSuperview];
    }

    if ([self.updateItem isCriticalUpdate]) {
        self.skipButton.enabled = NO;
        self.skipButton.hidden = YES;
        self.laterButton.enabled = NO;
        self.laterButton.hidden = YES;
    }

    if (![self automaticChecksEnabled]) {
        self.laterButton.enabled = NO;
        self.laterButton.hidden = YES;
    }
    
    [self.window center];
}

- (BOOL)automaticChecksEnabled {
    NSNumber *automaticChecksEnabled = [self.host objectForInfoDictionaryKey:SUEnableAutomaticChecksKey];
    if (automaticChecksEnabled == nil)
    {
        return false;
    }

    return [automaticChecksEnabled boolValue];
}

- (BOOL)windowShouldClose:(NSNotification *) __unused note
{
	[self endWithSelection:SURemindMeLaterChoice];
	return YES;
}

- (NSImage *)applicationIcon
{
    return [SUApplicationInfo bestIconForHost:self.host];
}

- (NSString *)titleText
{
    return [NSString stringWithFormat:SULocalizedString(@"A new version of %@ is available!", nil), [self.host name]];
}

- (NSString *)descriptionText
{
    NSString *updateItemVersion = [self.updateItem displayVersionString];
    NSString *hostVersion = [self.host displayVersion];
    // Display more info if the version strings are the same; useful for betas.
    if (!self.versionDisplayer && [updateItemVersion isEqualToString:hostVersion] ) {
        updateItemVersion = [updateItemVersion stringByAppendingFormat:@" (%@)", [self.updateItem versionString]];
        hostVersion = [hostVersion stringByAppendingFormat:@" (%@)", self.host.version];
    } else {
        [self.versionDisplayer formatVersion:&updateItemVersion andVersion:&hostVersion];
    }

    // We display a slightly different summary depending on if it's an "info-only" item or not
    NSString *finalString = nil;

    if (self.updateItem.isInformationOnlyUpdate) {
        finalString = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is now available--you have %@. Would you like to learn more about this update on the web?", @"Description text for SUUpdateAlert when the update informational with no download."), self.host.name, updateItemVersion, hostVersion];
    } else {
        finalString = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is now available--you have %@. Would you like to download it now?", @"Description text for SUUpdateAlert when the update is downloadable."), self.host.name, updateItemVersion, hostVersion];
    }
    return finalString;
}

- (void)adaptReleaseNotesAppearance
{
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101400
    if (SUAVAILABLE(10, 14))
    {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability"
        NSAppearanceName bestAppearance = [self.window.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        BOOL isDarkAqua = ([bestAppearance isEqualToString:NSAppearanceNameDarkAqua]);
        self.releaseNotesView.preferences.userStyleSheetEnabled = isDarkAqua;
#pragma clang diagnostic pop
    }
#endif
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    if ([frame parentFrame] == nil) {
        self.webViewFinishedLoading = YES;
        [self.releaseNotesSpinner setHidden:YES];
        [sender display]; // necessary to prevent weird scroll bar artifacting
    }
}

- (void)webView:(WebView *)__unused sender decidePolicyForNavigationAction:(NSDictionary *)__unused actionInformation request:(NSURLRequest *)request frame:(WebFrame *)__unused frame decisionListener:(id<WebPolicyDecisionListener>)listener
{
    NSURL *requestURL = request.URL;
    NSString *scheme = requestURL.scheme;
    BOOL isAboutBlank = [requestURL.absoluteString isEqualToString:@"about:blank"];
    BOOL whitelistedSafe = [scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"] || isAboutBlank;

    // Do not allow redirects to dangerous protocols such as file://
    if (!whitelistedSafe) {
        SULog(SULogLevelDefault, @"Blocked display of %@ URL which may be dangerous", scheme);
        [listener ignore];
        return;
    }

    if (self.webViewFinishedLoading) {
        if (requestURL && !isAboutBlank) {
            [[NSWorkspace sharedWorkspace] openURL:requestURL];
        }

        [listener ignore];
    }
    else {
        [listener use];
    }
}

// Clean up the contextual menu.
- (NSArray<NSMenuItem *> *)webView:(WebView *)__unused sender contextMenuItemsForElement:(NSDictionary *)__unused element defaultMenuItems:(NSArray<NSMenuItem *> *)defaultMenuItems
{
    NSMutableArray<NSMenuItem *> *webViewMenuItems = [defaultMenuItems mutableCopy];

	if (webViewMenuItems)
	{
		for (NSMenuItem *menuItem in defaultMenuItems)
		{
            NSInteger tag = [menuItem tag];

			switch (tag)
			{
                case WebMenuItemTagOpenLinkInNewWindow:
                case WebMenuItemTagDownloadLinkToDisk:
                case WebMenuItemTagOpenImageInNewWindow:
                case WebMenuItemTagDownloadImageToDisk:
                case WebMenuItemTagOpenFrameInNewWindow:
                case WebMenuItemTagGoBack:
                case WebMenuItemTagGoForward:
                case WebMenuItemTagStop:
                case WebMenuItemTagReload:
                    [webViewMenuItems removeObjectIdenticalTo:menuItem];
            }
        }
    }

    return webViewMenuItems;
}

- (NSTouchBar *)makeTouchBar
{
    NSTouchBar *touchBar = [(NSTouchBar *)[NSClassFromString(@"NSTouchBar") alloc] init];
    touchBar.defaultItemIdentifiers = @[SUUpdateAlertTouchBarIndentifier,];
    touchBar.principalItemIdentifier = SUUpdateAlertTouchBarIndentifier;
    touchBar.delegate = self;
    return touchBar;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar * __unused)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier API_AVAILABLE(macos(10.12.2))
{
    if ([identifier isEqualToString:SUUpdateAlertTouchBarIndentifier]) {
        NSCustomTouchBarItem* item = [(NSCustomTouchBarItem *)[NSClassFromString(@"NSCustomTouchBarItem") alloc] initWithIdentifier:identifier];
        item.viewController = [[SUTouchBarButtonGroup alloc] initByReferencingButtons:@[self.installButton, self.laterButton, self.skipButton]];
        return item;
    }
    return nil;
}

@end
