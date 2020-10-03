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
#import "SPUDownloadData.h"
#import "SUApplicationInfo.h"
#import "SPUUpdaterSettings.h"
#import "SUSystemUpdateInfo.h"
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
#endif

@interface SUUpdateAlert () <WebFrameLoadDelegate, WebPolicyDelegate, NSTouchBarDelegate>

@property (strong) SUAppcastItem *updateItem;
@property (nonatomic) BOOL alreadyDownloaded;
@property (strong) SUHost *host;
@property (nonatomic) BOOL allowsAutomaticUpdates;
@property (nonatomic, copy, nullable) void(^completionBlock)(SPUUpdateAlertChoice);
@property (nonatomic, copy, nullable) void(^resumableCompletionBlock)(SPUInstallUpdateStatus);
@property (nonatomic, copy, nullable) void(^informationalCompletionBlock)(SPUInformationalUpdateAlertChoice);

@property (strong) NSProgressIndicator *releaseNotesSpinner;
@property (assign) BOOL webViewFinishedLoading;

@property (strong) IBOutlet WebView *releaseNotesView;
@property (weak) IBOutlet NSView *releaseNotesContainerView;
@property (weak) IBOutlet NSTextField *descriptionField;
@property (weak) IBOutlet NSButton *automaticallyInstallUpdatesButton;
@property (weak) IBOutlet NSButton *installButton;
@property (weak) IBOutlet NSButton *skipButton;
@property (weak) IBOutlet NSButton *laterButton;

@property (strong) NSBox *darkBackgroundView;
@property (assign) BOOL observingAppearance;

@end

@implementation SUUpdateAlert

@synthesize completionBlock = _completionBlock;
@synthesize alreadyDownloaded = _alreadyDownloaded;
@synthesize resumableCompletionBlock = _resumableCompletionBlock;
@synthesize informationalCompletionBlock = _informationalCompletionBlock;
@synthesize versionDisplayer;

@synthesize updateItem;
@synthesize host;
@synthesize allowsAutomaticUpdates = _allowsAutomaticUpdates;

@synthesize releaseNotesSpinner;
@synthesize webViewFinishedLoading;

@synthesize releaseNotesView;
@synthesize releaseNotesContainerView;
@synthesize descriptionField;
@synthesize automaticallyInstallUpdatesButton;
@synthesize installButton;
@synthesize skipButton;
@synthesize laterButton;

@synthesize darkBackgroundView = _darkBackgroundView;
@synthesize observingAppearance;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item host:(SUHost *)aHost versionDisplayer:(id <SUVersionDisplay>)aVersionDisplayer
{
    self = [super initWithWindowNibName:@"SUUpdateAlert"];
    if (self != nil) {
        host = aHost;
        updateItem = item;
        versionDisplayer = aVersionDisplayer;
        
        SPUUpdaterSettings *updaterSettings = [[SPUUpdaterSettings alloc] initWithHostBundle:host.bundle];
        _allowsAutomaticUpdates = updaterSettings.allowsAutomaticUpdates && !item.isInformationOnlyUpdate;
        [self setShouldCascadeWindows:NO];
        
        // Alex: This dummy line makes sure that the binary is linked against WebKit.
        // The SUUpdateAlert.xib file contains a WebView and if we don't link against WebKit,
        // we will get a runtime crash when decoding the NIB. It is better to get a link error.
        [WebView MIMETypesShownAsHTML];
    }
    return self;
}

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item alreadyDownloaded:(BOOL)alreadyDownloaded host:(SUHost *)aHost versionDisplayer:(id <SUVersionDisplay>)aVersionDisplayer completionBlock:(void (^)(SPUUpdateAlertChoice))block
{
    self = [self initWithAppcastItem:item host:aHost versionDisplayer:aVersionDisplayer];
	if (self != nil)
	{
        _completionBlock = [block copy];
        _alreadyDownloaded = alreadyDownloaded;
    }
    return self;
}

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item host:(SUHost *)aHost versionDisplayer:(id <SUVersionDisplay>)aVersionDisplayer resumableCompletionBlock:(void (^)(SPUInstallUpdateStatus))block
{
    self = [self initWithAppcastItem:item host:aHost versionDisplayer:aVersionDisplayer];
    if (self != nil)
    {
        _resumableCompletionBlock = [block copy];
        _alreadyDownloaded = YES;
    }
    return self;
}

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item host:(SUHost *)aHost versionDisplayer:(id <SUVersionDisplay>)aVersionDisplayer informationalCompletionBlock:(void (^)(SPUInformationalUpdateAlertChoice))block
{
    self = [self initWithAppcastItem:item host:aHost versionDisplayer:aVersionDisplayer];
    if (self != nil)
    {
        _informationalCompletionBlock = [block copy];
    }
    return self;
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], [self.host bundlePath]]; }

- (void)disableKeyboardShortcutForInstallButton {
    self.installButton.keyEquivalent = @"";
}

- (void)endWithSelection:(SPUUpdateAlertChoice)choice
{
    [self.releaseNotesView stopLoading:self];
    [self.releaseNotesView setFrameLoadDelegate:nil];
    [self.releaseNotesView setPolicyDelegate:nil];
    [self.releaseNotesView removeFromSuperview]; // Otherwise it gets sent Esc presses (why?!) and gets very confused.
    [self close];
    
    if (self.completionBlock != nil) {
        self.completionBlock(choice);
        self.completionBlock = nil;
    } else if (self.resumableCompletionBlock != nil) {
        switch (choice) {
            case SPUInstallUpdateChoice:
                self.resumableCompletionBlock(SPUInstallAndRelaunchUpdateNow);
                break;
            case SPUInstallLaterChoice:
                self.resumableCompletionBlock(SPUDismissUpdateInstallation);
                break;
            case SPUSkipThisVersionChoice:
                abort();
        }
        self.resumableCompletionBlock = nil;
    } else if (self.informationalCompletionBlock != nil) {
        switch (choice) {
            case SPUInstallLaterChoice:
                self.informationalCompletionBlock(SPUDismissInformationalNoticeChoice);
                break;
            case SPUSkipThisVersionChoice:
                self.informationalCompletionBlock(SPUSkipThisInformationalVersionChoice);
                break;
            case SPUInstallUpdateChoice:
                abort();
        }
    }
}

- (IBAction)installUpdate:(id)__unused sender
{
    [self endWithSelection:SPUInstallUpdateChoice];
}

- (IBAction)openInfoURL:(id)__unused sender
{
    [[NSWorkspace sharedWorkspace] openURL:self.updateItem.infoURL];
    
    [self endWithSelection:SPUInstallLaterChoice];
}

- (IBAction)skipThisVersion:(id)__unused sender
{
    [self endWithSelection:SPUSkipThisVersionChoice];
}

- (IBAction)remindMeLater:(id)__unused sender
{
    [self endWithSelection:SPUInstallLaterChoice];
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
    
    // Set the default font
    // "-apple-system-font" is a reference to the system UI font. "-apple-system" is the new recommended token, but for backward compatibility we can't use it.
    prefs.standardFontFamily = @"-apple-system-font";
    prefs.defaultFontSize = (int)[NSFont systemFontSize];
    [self adaptReleaseNotesAppearance];

#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101400
    if (@available(macOS 10.14, *)) {
        if (!self.observingAppearance) {
            [self.releaseNotesView addObserver:self forKeyPath:@"effectiveAppearance" options:0 context:nil];
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
    
    // If there's no release notes URL, just stick the contents of the description into the web view
    // Otherwise we'll wait until the client wants us to show release notes
	if (self.updateItem.releaseNotesURL == nil)
	{
        [[self.releaseNotesView mainFrame] loadHTMLString:[self.updateItem itemDescription] baseURL:nil];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(__attribute__((unused)) NSDictionary<NSKeyValueChangeKey,id> *)change context:(__attribute__((unused)) void *)context {
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101400
    if (@available(macOS 10.14, *)) {
        if (object == self.releaseNotesView && [keyPath isEqualToString:@"effectiveAppearance"]) {
            [self adaptReleaseNotesAppearance];
        }
    }
#endif
}

- (void)dealloc {
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101400
    if (@available(macOS 10.14, *)) {
        if (self.observingAppearance) {
            [self.releaseNotesView removeObserver:self forKeyPath:@"effectiveAppearance"];
            self.observingAppearance = NO;
        }
    }
#endif
}

- (void)adaptReleaseNotesAppearance
{
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101400
    if (@available(macOS 10.14, *))
    {
        WebPreferences *prefs = [self.releaseNotesView preferences];
        NSAppearanceName bestAppearance = [self.releaseNotesView.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        if ([bestAppearance isEqualToString:NSAppearanceNameDarkAqua])
        {
            // Set user stylesheet adapted to light on dark
            prefs.userStyleSheetEnabled = YES;
            prefs.userStyleSheetLocation = [[NSBundle bundleForClass:[self class]] URLForResource:@"DarkAqua" withExtension:@"css"];
            
            // Remove web view background...
            self.releaseNotesView.drawsBackground = NO;
            // ... and use NSBox to get the dynamically colored background
            if (self.darkBackgroundView == nil)
            {
                self.darkBackgroundView = [[NSBox alloc] initWithFrame:self.releaseNotesView.frame];
                self.darkBackgroundView.boxType = NSBoxCustom;
                self.darkBackgroundView.fillColor = [NSColor textBackgroundColor];
                self.darkBackgroundView.borderColor = [NSColor clearColor];
                // Using auto-resizing mask instead of contraints works well enough
                self.darkBackgroundView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
                [self.releaseNotesView.superview addSubview:self.darkBackgroundView positioned:NSWindowBelow relativeTo:self.releaseNotesView];
                
                // The release note user stylesheet will not adjust to the user changing the theme until adaptReleaseNoteAppearance is called again.
                // So lock the appearance of the background to keep the text readable if the system theme changes.
                self.darkBackgroundView.appearance = self.darkBackgroundView.effectiveAppearance;
            }
        }
        else
        {
            // Restore standard dark on light appearance
            [self.darkBackgroundView removeFromSuperview];
            self.darkBackgroundView = nil;
            prefs.userStyleSheetEnabled = NO;
            self.releaseNotesView.drawsBackground = YES;
        }
    }
#endif
}

- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData
{
    if (!self.webViewFinishedLoading) {
        NSURL *baseURL = self.updateItem.releaseNotesURL.URLByDeletingLastPathComponent;
        // If a MIME type isn't provided, we will pick html as the default, as opposed to plain text. Questionable decision..
        NSString *chosenMIMEType = (downloadData.MIMEType != nil) ? downloadData.MIMEType : @"text/html";
        // We'll pick utf-8 as the default text encoding name if one isn't provided which I think is reasonable
        NSString *chosenTextEncodingName = (downloadData.textEncodingName != nil) ? downloadData.textEncodingName : @"utf-8";
        
        [[self.releaseNotesView mainFrame] loadData:downloadData.data MIMEType:chosenMIMEType textEncodingName:chosenTextEncodingName baseURL:baseURL];
    }
}

- (void)showReleaseNotesFailedToDownload
{
    [self stopReleaseNotesSpinner];
    self.webViewFinishedLoading = YES;
}

- (void)stopReleaseNotesSpinner
{
    [self.releaseNotesSpinner stopAnimation:self];
    [self.releaseNotesSpinner setHidden:YES];
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
    
    BOOL startedInstalling = (self.resumableCompletionBlock != nil);
    if (startedInstalling) {
        // Should we hide the button or disable the button if the update has already started installing?
        // Personally I think it looks better when the button is visible on the window...
        // Anyway an already downloaded update can't be skipped
        self.skipButton.enabled = NO;
        
        // We're going to be relaunching pretty instantaneously
        self.installButton.title = SULocalizedString(@"Install & Relaunch", nil);
        
        // We should be explicit that the update will be installed on quit
        self.laterButton.title = SULocalizedString(@"Install on Quit", nil);
    }

    if ([self.updateItem isCriticalUpdate]) {
        self.skipButton.enabled = NO;
    }

    [self.window center];
}

- (BOOL)windowShouldClose:(NSNotification *) __unused note
{
	[self endWithSelection:SPUInstallLaterChoice];
	return YES;
}

- (NSImage *)applicationIcon
{
    return [SUApplicationInfo bestIconForHost:self.host];
}

- (NSString *)titleText
{
    if ([self.updateItem isCriticalUpdate])
    {
        return [NSString stringWithFormat:SULocalizedString(@"An important update to %@ is ready to install", nil), [self.host name]];
    }
    else if (self.alreadyDownloaded)
    {
        return [NSString stringWithFormat:SULocalizedString(@"A new version of %@ is ready to install!", nil), [self.host name]];
    }
    else
    {
        return [NSString stringWithFormat:SULocalizedString(@"A new version of %@ is available!", nil), [self.host name]];
    }
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

    // We display a different summary depending on if it's an "info-only" item, or a "critical update" item, or if we've already downloaded the update and just need to relaunch
    NSString *finalString = nil;

    if (self.updateItem.isInformationOnlyUpdate) {
        finalString = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is now available--you have %@. Would you like to learn more about this update on the web?", @"Description text for SUUpdateAlert when the update informational with no download."), self.host.name, updateItemVersion, hostVersion];
    } else if ([self.updateItem isCriticalUpdate]) {
        if (!self.alreadyDownloaded) {
            finalString = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is now available--you have %@. This is an important update; would you like to download it now?", @"Description text for SUUpdateAlert when the critical update is downloadable."), self.host.name, updateItemVersion, hostVersion];
        } else {
            finalString = [NSString stringWithFormat:SULocalizedString(@"%1$@ %2$@ has been downloaded and is ready to use! This is an important update; would you like to install it and relaunch %1$@ now?", @"Description text for SUUpdateAlert when the critical update has already been downloaded and ready to install."), self.host.name, updateItemVersion];
        }
    } else {
        if (!self.alreadyDownloaded) {
            finalString = [NSString stringWithFormat:SULocalizedString(@"%@ %@ is now available--you have %@. Would you like to download it now?", @"Description text for SUUpdateAlert when the update is downloadable."), self.host.name, updateItemVersion, hostVersion];
        } else {
            finalString = [NSString stringWithFormat:SULocalizedString(@"%1$@ %2$@ has been downloaded and is ready to use! Would you like to install it and relaunch %1$@ now?", @"Description text for SUUpdateAlert when the update has already been downloaded and ready to install."), self.host.name, updateItemVersion];
        }
    }
    return finalString;
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    if ([frame parentFrame] == nil) {
        [self stopReleaseNotesSpinner];
        self.webViewFinishedLoading = YES;
        [sender display]; // necessary to prevent weird scroll bar artifacting
    }
}

- (void)webView:(WebView *)__unused sender decidePolicyForNavigationAction:(NSDictionary *)__unused actionInformation request:(NSURLRequest *)request frame:(WebFrame *)__unused frame decisionListener:(id<WebPolicyDecisionListener>)listener
{
    NSURL *requestURL = request.URL;
    NSString *scheme = requestURL.scheme;
    BOOL isAboutBlank = [requestURL.absoluteString isEqualToString:@"about:blank"];
    BOOL whitelistedSafe = isAboutBlank || [@[@"http", @"https", @"macappstore", @"macappstores", @"itms-apps", @"itms-appss"] containsObject:scheme];

    // Do not allow redirects to dangerous protocols such as file://
    if (!whitelistedSafe) {
        SULog(SULogLevelDefault, @"Blocked display of %@ URL which may be dangerous", scheme);
        [listener ignore];
        return;
    }

    if (self.webViewFinishedLoading) {
        if (requestURL) {
            [[NSWorkspace sharedWorkspace] openURL:requestURL];
        }

        [listener ignore];
    }
    else {
        [listener use];
    }
}

// Clean up the contextual menu.
- (NSArray *)webView:(WebView *)__unused sender contextMenuItemsForElement:(NSDictionary *)__unused element defaultMenuItems:(NSArray *)defaultMenuItems
{
    NSMutableArray *webViewMenuItems = [defaultMenuItems mutableCopy];

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
