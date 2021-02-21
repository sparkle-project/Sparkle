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
#import "SUWebView.h"
#import "SUWKWebView.h"
#import "SULegacyWebView.h"

#import "SUConstants.h"
#import "SULog.h"
#import "SULocalizations.h"
#import "SUAppcastItem.h"
#import "SPUDownloadData.h"
#import "SUApplicationInfo.h"
#import "SPUUpdaterSettings.h"
#import "SUTouchBarForwardDeclarations.h"
#import "SUTouchBarButtonGroup.h"
#import "SPUXPCServiceInfo.h"

static NSString *const SUUpdateAlertTouchBarIndentifier = @"" SPARKLE_BUNDLE_IDENTIFIER ".SUUpdateAlert";

@interface SUUpdateAlert () <NSTouchBarDelegate>

@property (strong) SUAppcastItem *updateItem;
@property (nonatomic) BOOL alreadyDownloaded;
@property (strong) SUHost *host;
@property (nonatomic) BOOL allowsAutomaticUpdates;
@property (nonatomic, copy, nullable) void(^completionBlock)(SPUUpdateAlertChoice);
@property (nonatomic, copy, nullable) void(^resumableCompletionBlock)(SPUInstallUpdateStatus);
@property (nonatomic, copy, nullable) void(^informationalCompletionBlock)(SPUInformationalUpdateAlertChoice);

@property (strong) NSProgressIndicator *releaseNotesSpinner;

@property (weak) IBOutlet NSView *releaseNotesContainerView;
@property (weak) IBOutlet NSBox *releaseNotesBoxView;
@property (weak) IBOutlet NSTextField *descriptionField;
@property (weak) IBOutlet NSButton *automaticallyInstallUpdatesButton;
@property (weak) IBOutlet NSButton *installButton;
@property (weak) IBOutlet NSButton *skipButton;
@property (weak) IBOutlet NSButton *laterButton;

@property (strong) NSBox *darkBackgroundView;
@property (assign) BOOL observingAppearance;

@property (nonatomic) id<SUWebView> webView;

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

@synthesize releaseNotesContainerView;
@synthesize releaseNotesBoxView = _releaseNotesBoxView;
@synthesize descriptionField;
@synthesize automaticallyInstallUpdatesButton;
@synthesize installButton;
@synthesize skipButton;
@synthesize laterButton;

@synthesize darkBackgroundView = _darkBackgroundView;
@synthesize observingAppearance;

@synthesize webView = _webView;

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
    [self.webView stopLoading];
    [self.webView.view removeFromSuperview]; // Otherwise it gets sent Esc presses (why?!) and gets very confused.
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
    [self adaptReleaseNotesAppearance];

#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101400
    if (@available(macOS 10.14, *)) {
        if (!self.observingAppearance) {
            [self.webView.view addObserver:self forKeyPath:@"effectiveAppearance" options:0 context:nil];
            self.observingAppearance = YES;
        }
    }
#endif
    
    // Stick a nice big spinner in the middle of the web view until the page is loaded.
    NSRect frame = [[self.webView.view superview] frame];
    self.releaseNotesSpinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(NSMidX(frame) - 16, NSMidY(frame) - 16, 32, 32)];
    [self.releaseNotesSpinner setStyle:NSProgressIndicatorSpinningStyle];
    [self.releaseNotesSpinner startAnimation:self];
    [[self.webView.view superview] addSubview:self.releaseNotesSpinner];
    
    // If there's no release notes URL, just stick the contents of the description into the web view
    // Otherwise we'll wait until the client wants us to show release notes
	if (self.updateItem.releaseNotesURL == nil)
	{
        __weak __typeof__(self) weakSelf = self;
        [self.webView loadHTMLString:[self.updateItem itemDescription] baseURL:nil completionHandler:^(NSError * _Nullable error) {
            if (error != nil) {
                SULog(SULogLevelError, @"Failed to load HTML string from web view: %@", error);
            }
            [weakSelf stopReleaseNotesSpinner];
        }];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(__attribute__((unused)) NSDictionary<NSKeyValueChangeKey,id> *)change context:(__attribute__((unused)) void *)context {
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101400
    if (@available(macOS 10.14, *)) {
        if (object == self.webView.view && [keyPath isEqualToString:@"effectiveAppearance"]) {
            [self adaptReleaseNotesAppearance];
        }
    }
#endif
}

- (void)dealloc {
#if __MAC_OS_X_VERSION_MAX_ALLOWED >= 101400
    if (@available(macOS 10.14, *)) {
        if (self.observingAppearance) {
            [self.webView.view removeObserver:self forKeyPath:@"effectiveAppearance"];
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
        NSAppearanceName bestAppearance = [self.webView.view.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        if ([bestAppearance isEqualToString:NSAppearanceNameDarkAqua])
        {
            // Remove web view background...
            [self.webView setDrawsBackground:NO];
            // ... and use NSBox to get the dynamically colored background
            if (self.darkBackgroundView == nil)
            {
                self.darkBackgroundView = [[NSBox alloc] initWithFrame:self.webView.view.frame];
                self.darkBackgroundView.boxType = NSBoxCustom;
                self.darkBackgroundView.fillColor = [NSColor textBackgroundColor];
                self.darkBackgroundView.borderColor = [NSColor clearColor];
                // Using auto-resizing mask instead of contraints works well enough
                self.darkBackgroundView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
                [self.webView.view.superview addSubview:self.darkBackgroundView positioned:NSWindowBelow relativeTo:self.webView.view];
                
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
            [self.webView setDrawsBackground:YES];
        }
    }
#endif
}

- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData
{
    NSURL *baseURL = self.updateItem.releaseNotesURL.URLByDeletingLastPathComponent;
    // If a MIME type isn't provided, we will pick html as the default, as opposed to plain text. Questionable decision..
    NSString *chosenMIMEType = (downloadData.MIMEType != nil) ? downloadData.MIMEType : @"text/html";
    // We'll pick utf-8 as the default text encoding name if one isn't provided which I think is reasonable
    NSString *chosenTextEncodingName = (downloadData.textEncodingName != nil) ? downloadData.textEncodingName : @"utf-8";
    
    __weak __typeof__(self) weakSelf = self;
    [self.webView loadData:downloadData.data MIMEType:chosenMIMEType textEncodingName:chosenTextEncodingName baseURL:baseURL completionHandler:^(NSError * _Nullable error) {
        if (error != nil) {
            SULog(SULogLevelError, @"Failed to load data from web view: %@", error);
        }
        [weakSelf stopReleaseNotesSpinner];
    }];
}

- (void)showReleaseNotesFailedToDownload
{
    [self stopReleaseNotesSpinner];
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
    
    if (showReleaseNotes) {
        NSURL *colorStyleURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"ReleaseNotesColorStyle" withExtension:@"css"];
        
        // "-apple-system-font" is a reference to the system UI font. "-apple-system" is the new recommended token, but for backward compatibility we can't use it.
        NSString *defaultFontFamily = @"-apple-system-font";
        int defaultFontSize = (int)[NSFont systemFontSize];
        
        BOOL javaScriptEnabled = [self.host boolForInfoDictionaryKey:SUEnableJavaScriptKey];
        
        BOOL useWKWebView;
        if (@available(macOS 10.11, *)) {
            // WKWebView has a bug where it won't work in loading local HTML content in sandboxed apps that do not have an outgoing network entitlement
            // FB6993802: https://twitter.com/sindresorhus/status/1160577243929878528 | https://github.com/feedback-assistant/reports/issues/1
            // If the developer is using the downloader XPC service, they are very most likely are a) sandboxed b) do not use outgoing network entitlement.
            // In this case, fall back to legacy WebKit view.
            // (In theory it is possible for a non-sandboxed app or sandboxed app with outgoing network entitlement to use the XPC service, it's just pretty unlikely. And falling back to a legacy web view would not be too harmful in those cases).
            useWKWebView = !SPUXPCServiceExists(@DOWNLOADER_BUNDLE_ID);
        } else {
            // Never use WKWebView prior to macOS 10.11. Details are in SUWKWebView.m
            useWKWebView = NO;
        }
        
        if (useWKWebView) {
            self.webView = [[SUWKWebView alloc] initWithColorStyleSheetLocation:colorStyleURL fontFamily:defaultFontFamily fontPointSize:defaultFontSize javaScriptEnabled:javaScriptEnabled];
        } else {
            self.webView = [[SULegacyWebView alloc] initWithColorStyleSheetLocation:colorStyleURL fontFamily:defaultFontFamily fontPointSize:defaultFontSize javaScriptEnabled:javaScriptEnabled];
        }
        
        NSView *boxContentView = self.releaseNotesBoxView.contentView;
        [boxContentView addSubview:self.webView.view];
        
        self.webView.view.frame = boxContentView.bounds;
        self.webView.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    }

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
    
    // NOTE: The code below for deciding what buttons to hide is complex! Due to array of feature configurations :)
    
    // When we show release notes, it looks ugly if the install buttons are not closer to the release notes view
    // However when we don't show release notes, it looks ugly if the install buttons are too close to the description field. Shrugs.
    if (!self.allowsAutomaticUpdates) {
        if (showReleaseNotes) {
            // Fix constraints so that buttons aren't far away from web view when we hide the automatic updates check box
            NSLayoutConstraint *skipButtonToReleaseNotesContainerConstraint = [NSLayoutConstraint constraintWithItem:self.skipButton attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.releaseNotesContainerView attribute:NSLayoutAttributeBottom multiplier:1.0 constant:12.0];
            
            [self.window.contentView addConstraint:skipButtonToReleaseNotesContainerConstraint];
            
            [self.automaticallyInstallUpdatesButton removeFromSuperview];
        } else {
            // Disable automatic install updates option if the developer wishes for it in Info.plist
            // If we are showing release notes, this button will be hidden instead
            self.automaticallyInstallUpdatesButton.enabled = NO;
        }
    }
    
    BOOL startedInstalling = (self.resumableCompletionBlock != nil);
    if (startedInstalling) {
        // An already downloaded & resumable update can't be skipped
        self.skipButton.hidden = YES;
        
        // We're going to be relaunching pretty instantaneously
        self.installButton.title = SULocalizedString(@"Install and Relaunch", nil);
        
        // We should be explicit that the update will be installed on quit
        self.laterButton.title = SULocalizedString(@"Install on Quit", @"Alternate title for 'Remind Me Later' button when downloaded updates can be resumed");
    }

    if ([self.updateItem isCriticalUpdate]) {
        self.skipButton.hidden = YES;
        self.laterButton.hidden = YES;
    }
    
    // Reminding user later doesn't make sense when automatic update checks are off
    if (![self.host boolForKey:SUEnableAutomaticChecksKey]) {
        self.laterButton.hidden = YES;
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
