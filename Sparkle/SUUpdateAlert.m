//
//  SUUpdateAlert.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

// -----------------------------------------------------------------------------
// Headers:
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
#import "SUApplicationInfo.h"
#import "SUSystemUpdateInfo.h"
#import "SUOperatingSystem.h"
#import "SUTouchBarForwardDeclarations.h"
#import "SUTouchBarButtonGroup.h"

static NSString *const SUUpdateAlertTouchBarIndentifier = @"" SPARKLE_BUNDLE_IDENTIFIER ".SUUpdateAlert";

@interface SUUpdateAlert () <NSTouchBarDelegate>

@property (strong) SUAppcastItem *updateItem;
@property (strong) SUHost *host;
@property (strong) void(^completionBlock)(SUUpdateAlertChoice);

@property (strong) NSProgressIndicator *releaseNotesSpinner;
@property (assign) BOOL observingAppearance;
@property (weak) IBOutlet NSView *releaseNotesContainerView;
@property (weak) IBOutlet NSBox *releaseNotesBoxView;
@property (weak) IBOutlet NSTextField *descriptionField;
@property (weak) IBOutlet NSButton *automaticallyInstallUpdatesButton;
@property (weak) IBOutlet NSButton *installButton;
@property (weak) IBOutlet NSButton *skipButton;
@property (weak) IBOutlet NSButton *laterButton;

@property (strong) NSBox *darkBackgroundView;

@property (nonatomic) id<SUWebView> webView;

@property (nonatomic) NSDictionary *httpHeaders;
@property (nonatomic) NSString *userAgent;

@end

@implementation SUUpdateAlert

@synthesize completionBlock;
@synthesize versionDisplayer;

@synthesize updateItem;
@synthesize host;

@synthesize releaseNotesSpinner;
@synthesize observingAppearance;

@synthesize releaseNotesContainerView;
@synthesize releaseNotesBoxView = _releaseNotesBoxView;
@synthesize descriptionField;
@synthesize automaticallyInstallUpdatesButton;
@synthesize installButton;
@synthesize skipButton;
@synthesize laterButton;

@synthesize darkBackgroundView = _darkBackgroundView;

@synthesize webView = _webView;

@synthesize httpHeaders = _httpHeaders;
@synthesize userAgent = _userAgent;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item httpHeaders:(NSDictionary *)httpHeaders userAgent:(NSString *)userAgent host:(SUHost *)aHost completionBlock:(void (^)(SUUpdateAlertChoice))block
{
    self = [super initWithWindowNibName:@"SUUpdateAlert"];
    if (self)
    {
        self.completionBlock = block;
        host = aHost;
        updateItem = item;
        _httpHeaders = httpHeaders;
        _userAgent = userAgent;
        [self setShouldCascadeWindows:NO];
    }
    return self;
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], [self.host bundlePath]]; }

- (void)disableKeyboardShortcutForInstallButton {
    self.installButton.keyEquivalent = @"";
}

- (void)endWithSelection:(SUUpdateAlertChoice)choice
{
    [self.webView stopLoading];
    [self.webView.view removeFromSuperview]; // Otherwise it gets sent Esc presses (why?!) and gets very confused.
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

    // If there's a release notes URL, load it; otherwise, just stick the contents of the description into the web view.
    if ([self.updateItem releaseNotesURL])
    {
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[self.updateItem releaseNotesURL] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30];
        
        if (self.userAgent) {
            [request setValue:self.userAgent forHTTPHeaderField:@"User-Agent"];
        }

        if (self.httpHeaders) {
            for (NSString *key in self.httpHeaders) {
                NSString *value = [self.httpHeaders objectForKey:key];
                [request setValue:value forHTTPHeaderField:key];
            }
        }
        
        __weak __typeof__(self) weakSelf = self;
        [self.webView loadRequest:request completionHandler:^(NSError * _Nullable error) {
            if (error != nil) {
                SULog(SULogLevelError, @"Failed to load URL request from web view: %@", error);
            }
            [weakSelf stopReleaseNotesSpinner];
        }];
    }
    else
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

- (BOOL)allowsAutomaticUpdates
{
    return [SUSystemUpdateInfo systemAllowsAutomaticUpdatesForHost:self.host]
            && !self.updateItem.isInformationOnlyUpdate;
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
            useWKWebView = YES;
        } else {
            // Never use WKWebView prior to macOS 10.11. Details are in SUWKWebView.m
            // Note: 2.x has another case where we fall back to using legacy WKWebView due to certain sandboxing issues.
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
    BOOL allowsAutomaticUpdates = [self allowsAutomaticUpdates];
    // Automatic downloads is enabled by developer if they set SUAutomaticallyUpdateKey in Info.plist,
    // rather than the user toggling the setting
    BOOL automaticDownloadsEnabledByDeveloper = [self.host boolForInfoDictionaryKey:SUAutomaticallyUpdateKey];
    if (!allowsAutomaticUpdates || automaticDownloadsEnabledByDeveloper) {
        if (showReleaseNotes) {
            // Fix constraints so that buttons aren't far away from web view when we hide the automatic updates check box
            NSLayoutConstraint *skipButtonToReleaseNotesContainerConstraint = [NSLayoutConstraint constraintWithItem:self.skipButton attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.releaseNotesContainerView attribute:NSLayoutAttributeBottom multiplier:1.0 constant:12.0];
            
            [self.window.contentView addConstraint:skipButtonToReleaseNotesContainerConstraint];
            
            [self.automaticallyInstallUpdatesButton removeFromSuperview];
        } else {
            self.automaticallyInstallUpdatesButton.enabled = NO;
        }
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
