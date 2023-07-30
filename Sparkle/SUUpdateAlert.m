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

#if SPARKLE_BUILD_UI_BITS

#import "SUUpdateAlert.h"

#import "SUHost.h"
#import "SUReleaseNotesView.h"
#import "SUWKWebView.h"
#import "SULegacyWebView.h"
#import "SUPlainTextReleaseNotesView.h"

#import "SUConstants.h"
#import "SULog.h"
#import "SULocalizations.h"
#import "SUAppcastItem.h"
#import "SPUDownloadData.h"
#import "SUApplicationInfo.h"
#import "SPUUpdaterSettings.h"
#import "SUTouchBarButtonGroup.h"
#import "SPUXPCServiceInfo.h"
#import "SPUUserUpdateState.h"

static NSString *const SUUpdateAlertTouchBarIndentifier = @"" SPARKLE_BUNDLE_IDENTIFIER ".SUUpdateAlert";

@interface SUUpdateAlert () <NSTouchBarDelegate>
@end

@implementation SUUpdateAlert
{
    SUAppcastItem *_updateItem;
    SUHost *_host;
    SPUUserUpdateState *_state;
    NSProgressIndicator *_releaseNotesSpinner;
    NSBox *_darkBackgroundView;
    id<SUReleaseNotesView> _releaseNotesView;
    id<SUVersionDisplay> _versionDisplayer;
    
    IBOutlet NSButton *_installButton;
    IBOutlet NSButton *_laterButton;
    IBOutlet NSButton *_skipButton;
    IBOutlet NSBox *_releaseNotesBoxView;
    IBOutlet NSTextField *_descriptionField;
    IBOutlet NSView *_releaseNotesContainerView;
    IBOutlet NSButton *_automaticallyInstallUpdatesButton;
    
    void (^_didBecomeKeyBlock)(void);
    void(^_completionBlock)(SPUUserUpdateChoice, NSRect, BOOL);
    
    BOOL _allowsAutomaticUpdates;
    BOOL _observingAppearance;
}

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state host:(SUHost *)aHost versionDisplayer:(id<SUVersionDisplay>)versionDisplayer completionBlock:(void (^)(SPUUserUpdateChoice, NSRect, BOOL))completionBlock didBecomeKeyBlock:(void (^)(void))didBecomeKeyBlock
{
    self = [super initWithWindowNibName:@"SUUpdateAlert"];
    if (self != nil) {
        _host = aHost;
        _updateItem = item;
        _versionDisplayer = versionDisplayer;
        
        _state = state;
        _completionBlock = [completionBlock copy];
        _didBecomeKeyBlock = [didBecomeKeyBlock copy];
        
        SPUUpdaterSettings *updaterSettings = [[SPUUpdaterSettings alloc] initWithHostBundle:aHost.bundle];
        
        BOOL allowsAutomaticUpdates;
        NSNumber *allowsAutomaticUpdatesOption = updaterSettings.allowsAutomaticUpdatesOption;
        if (item.informationOnlyUpdate) {
            allowsAutomaticUpdates = NO;
        } else if (allowsAutomaticUpdatesOption == nil) {
            allowsAutomaticUpdates = updaterSettings.automaticallyChecksForUpdates;
        } else {
            allowsAutomaticUpdates = allowsAutomaticUpdatesOption.boolValue;
        }
        _allowsAutomaticUpdates = allowsAutomaticUpdates;
        
        [self setShouldCascadeWindows:NO];
    } else {
        assert(false);
    }
    return self;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"%@ <%@>", [self class], _host.bundlePath];
}

- (void)setInstallButtonFocus:(BOOL)focus
{
    if (focus) {
        _installButton.keyEquivalent = @"\r";
    } else {
        _installButton.keyEquivalent = @"";
    }
}

- (void)endWithSelection:(SPUUserUpdateChoice)choice SPU_OBJC_DIRECT
{
    [_releaseNotesView stopLoading];
    [_releaseNotesView.view removeFromSuperview]; // Otherwise it gets sent Esc presses (why?!) and gets very confused.
    
    NSWindow *window = self.window;
    BOOL wasKeyWindow = window.keyWindow;
    NSRect windowFrame = window.frame;
    
    [self close];
    
    if (_completionBlock != nil) {
        _completionBlock(choice, windowFrame, wasKeyWindow);
        _completionBlock = nil;
    }
}

- (IBAction)installUpdate:(id)__unused sender
{
    [self endWithSelection:SPUUserUpdateChoiceInstall];
}

- (IBAction)openInfoURL:(id)__unused sender
{
    NSURL *infoURL = _updateItem.infoURL;
    assert(infoURL);
    
    [[NSWorkspace sharedWorkspace] openURL:infoURL];
    
    [self endWithSelection:SPUUserUpdateChoiceDismiss];
}

- (IBAction)skipThisVersion:(id)__unused sender
{
    [self endWithSelection:SPUUserUpdateChoiceSkip];
}

- (IBAction)remindMeLater:(id)__unused sender
{
    [self endWithSelection:SPUUserUpdateChoiceDismiss];
}

- (void)displayReleaseNotesSpinner SPU_OBJC_DIRECT
{
    // Stick a nice big spinner in the middle of the web view until the page is loaded.
    NSView *boxContentView = _releaseNotesBoxView.contentView;
    NSRect frame = boxContentView.frame;
    _releaseNotesSpinner = [[NSProgressIndicator alloc] initWithFrame:NSMakeRect(NSMidX(frame) - 16, NSMidY(frame) - 16, 32, 32)];
    [_releaseNotesSpinner setStyle:NSProgressIndicatorStyleSpinning];
    [_releaseNotesSpinner startAnimation:self];
    [boxContentView addSubview:_releaseNotesSpinner];
    
    // If there's no release notes URL, just stick the contents of the description into the web view
    // Otherwise we'll wait until the client wants us to show release notes
    if (_updateItem.releaseNotesURL == nil) {
        NSString *itemDescription = _updateItem.itemDescription;
        if (itemDescription != nil) {
            NSString *itemDescriptionFormat = _updateItem.itemDescriptionFormat;
            // We don't support markdown but prepare for the future in case we support it one day
            BOOL prefersPlainText =
                ([itemDescriptionFormat isEqualToString:@"plain-text"] ||
                 [itemDescriptionFormat isEqualToString:@"markdown"]);
            
            [self _createReleaseNotesViewPreferringPlainText:prefersPlainText];
            
            __weak __typeof__(self) weakSelf = self;
            [_releaseNotesView loadString:itemDescription baseURL:nil completionHandler:^(NSError * _Nullable error) {
                if (error != nil) {
                    SULog(SULogLevelError, @"Failed to load HTML string from web view: %@", error);
                }
                [weakSelf stopReleaseNotesSpinner];
            }];
        }
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(__attribute__((unused)) NSDictionary<NSKeyValueChangeKey,id> *)change context:(__attribute__((unused)) void *)context {
    if (@available(macOS 10.14, *)) {
        if (object == _releaseNotesView.view && [keyPath isEqualToString:@"effectiveAppearance"]) {
            [self adaptReleaseNotesAppearance];
        }
    }
}

- (void)dealloc {
    if (@available(macOS 10.14, *)) {
        if (_observingAppearance) {
            [_releaseNotesView.view removeObserver:self forKeyPath:@"effectiveAppearance"];
            _observingAppearance = NO;
        }
    }
}

- (void)adaptReleaseNotesAppearance SPU_OBJC_DIRECT
{
    if (@available(macOS 10.14, *)) {
        NSAppearanceName bestAppearance = [_releaseNotesView.view.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        if ([bestAppearance isEqualToString:NSAppearanceNameDarkAqua])
        {
            // Remove web view background...
            [_releaseNotesView setDrawsBackground:NO];
            // ... and use NSBox to get the dynamically colored background
            if (_darkBackgroundView == nil)
            {
                _darkBackgroundView = [[NSBox alloc] initWithFrame:_releaseNotesView.view.frame];
                _darkBackgroundView.boxType = NSBoxCustom;
                _darkBackgroundView.fillColor = [NSColor textBackgroundColor];
                _darkBackgroundView.borderColor = [NSColor clearColor];
                // Using auto-resizing mask instead of contraints works well enough
                _darkBackgroundView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
                [_releaseNotesView.view.superview addSubview:_darkBackgroundView positioned:NSWindowBelow relativeTo:_releaseNotesView.view];
                
                // The release note user stylesheet will not adjust to the user changing the theme until adaptReleaseNoteAppearance is called again.
                // So lock the appearance of the background to keep the text readable if the system theme changes.
                _darkBackgroundView.appearance = _darkBackgroundView.effectiveAppearance;
            }
        }
        else
        {
            // Restore standard dark on light appearance
            [_darkBackgroundView removeFromSuperview];
            _darkBackgroundView = nil;
            [_releaseNotesView setDrawsBackground:YES];
        }
        
        if (!_observingAppearance) {
            [_releaseNotesView.view addObserver:self forKeyPath:@"effectiveAppearance" options:0 context:nil];
            _observingAppearance = YES;
        }
    }
}

- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData
{
    if (![self showsReleaseNotes]) {
        if ([_host.bundle isEqual:NSBundle.mainBundle]) {
            SULog(SULogLevelError, @"Warning: '%@' is configured to not show release notes but release notes for version %@ were downloaded. Consider either removing release notes from your appcast or implementing -[SPUUpdaterDelegate updater:shouldDownloadReleaseNotesForUpdate:]", _host.name, _updateItem.displayVersionString);
        }
        return;
    }
    
    NSURL *releaseNotesURL = _updateItem.releaseNotesURL;
    NSURL *baseURL = releaseNotesURL.URLByDeletingLastPathComponent;
    // If a MIME type isn't provided, we will pick html as the default, as opposed to plain text. Questionable decision..
    NSString *chosenMIMEType = (downloadData.MIMEType != nil) ? downloadData.MIMEType : @"text/html";
    // We'll pick utf-8 as the default text encoding name if one isn't provided which I think is reasonable
    NSString *chosenTextEncodingName = (downloadData.textEncodingName != nil) ? downloadData.textEncodingName : @"utf-8";
    
    // We don't support markdown but prepare for the future in case we support it one day
    NSString *pathExtension = releaseNotesURL.pathExtension;
    BOOL preferringPlainText =
        ([chosenMIMEType isEqualToString:@"text/plain"] ||
         [pathExtension caseInsensitiveCompare:@"txt"] == NSOrderedSame ||
         [chosenMIMEType isEqualToString:@"text/markdown"] ||
         [chosenMIMEType isEqualToString:@"text/x-markdown"] ||
         [pathExtension caseInsensitiveCompare:@"md"] == NSOrderedSame ||
         [pathExtension caseInsensitiveCompare:@"markdown"] == NSOrderedSame);
    
    [self _createReleaseNotesViewPreferringPlainText:preferringPlainText];
    
    __weak __typeof__(self) weakSelf = self;
    [_releaseNotesView loadData:downloadData.data MIMEType:chosenMIMEType textEncodingName:chosenTextEncodingName baseURL:baseURL completionHandler:^(NSError * _Nullable error) {
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

- (void)stopReleaseNotesSpinner SPU_OBJC_DIRECT
{
    [_releaseNotesSpinner stopAnimation:self];
    [_releaseNotesSpinner setHidden:YES];
}

- (BOOL)showsReleaseNotes
{
    NSNumber *shouldShowReleaseNotes = [_host objectForInfoDictionaryKey:SUShowReleaseNotesKey];
    if (shouldShowReleaseNotes == nil) {
        // Don't show release notes if RSS item contains no description and no release notes URL:
        return (([_updateItem itemDescription] != nil
                 && [[[_updateItem itemDescription] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0)
                || [_updateItem releaseNotesURL] != nil);
    }
    else
        return [shouldShowReleaseNotes boolValue];
}

- (void)_createReleaseNotesViewPreferringPlainText:(BOOL)preferringPlainText SPU_OBJC_DIRECT
{
    // "-apple-system-font" is a reference to the system UI font. "-apple-system" is the new recommended token, but for backward compatibility we can't use it.
    NSString *defaultFontFamily = @"-apple-system-font";
    
    int defaultFontSize = (int)[NSFont systemFontSize];
    
    BOOL usesPlainText;
    if (preferringPlainText) {
        usesPlainText = YES;
    } else {
        if (@available(macOS 10.15, *)) {
            usesPlainText = [[NSProcessInfo processInfo] isMacCatalystApp];
            
            if (usesPlainText && !preferringPlainText) {
                SULog(SULogLevelError, @"Error: Showing HTML release notes for Catalyst apps is not supported. The release notes will be interpreted as plain text. Please serve a plain-text (.txt) release notes file. If you are using a <description> element then please specify the %@=\"plain-text\" attribute in that element.", SUAppcastAttributeFormat);
            }
        } else {
            usesPlainText = NO;
        }
    }
    
    NSArray<NSString *> *customAllowedURLSchemes;
    {
        NSMutableArray<NSString *> *allowedSchemes = [NSMutableArray array];
        id hostAllowedURLSchemes = [_host objectForInfoDictionaryKey:SUAllowedURLSchemesKey];
        if ([(NSObject *)hostAllowedURLSchemes isKindOfClass:[NSArray class]]) {
            for (id urlScheme in (NSArray *)hostAllowedURLSchemes) {
                if ([(NSObject *)urlScheme isKindOfClass:[NSString class]]) {
                    NSString *allowedURLScheme = [(NSString *)urlScheme lowercaseString];
                    if (![allowedURLScheme isEqualToString:@"file"]) {
                        [allowedSchemes addObject:allowedURLScheme];
                    } else {
                        SULog(SULogLevelError, @"Error: Found 'file' scheme in %@. Ignoring because this scheme is unsafe.", SUAllowedURLSchemesKey);
                    }
                }
            }
        }
        
        customAllowedURLSchemes = [allowedSchemes copy];
    }
    
    if (usesPlainText) {
        _releaseNotesView = [[SUPlainTextReleaseNotesView alloc] initWithFontPointSize:defaultFontSize customAllowedURLSchemes:customAllowedURLSchemes];
    } else {
        NSURL *colorStyleURL = [[NSBundle bundleForClass:[self class]] URLForResource:@"ReleaseNotesColorStyle" withExtension:@"css"];
        
        BOOL javaScriptEnabled = [_host boolForInfoDictionaryKey:SUEnableJavaScriptKey];
        
#if DOWNLOADER_XPC_SERVICE_EMBEDDED
        // WKWebView has a bug where it won't work in loading local HTML content in sandboxed apps that do not have an outgoing network entitlement
        // FB6993802: https://twitter.com/sindresorhus/status/1160577243929878528 | https://github.com/feedback-assistant/reports/issues/1
        // If the developer is using the downloader XPC service, they are very most likely are a) sandboxed b) do not use outgoing network entitlement.
        // In this case, fall back to legacy WebKit view.
        // (In theory it is possible for a non-sandboxed app or sandboxed app with outgoing network entitlement to use the XPC service, it's just pretty unlikely. And falling back to a legacy web view would not be too harmful in those cases).
        BOOL useWKWebView = !SPUXPCServiceIsEnabled(SUEnableDownloaderServiceKey);
        if (!useWKWebView) {
            _releaseNotesView = [[SULegacyWebView alloc] initWithColorStyleSheetLocation:colorStyleURL fontFamily:defaultFontFamily fontPointSize:defaultFontSize javaScriptEnabled:javaScriptEnabled customAllowedURLSchemes:customAllowedURLSchemes];
        } else
#endif
        {
            _releaseNotesView = [[SUWKWebView alloc] initWithColorStyleSheetLocation:colorStyleURL fontFamily:defaultFontFamily fontPointSize:defaultFontSize javaScriptEnabled:javaScriptEnabled customAllowedURLSchemes:customAllowedURLSchemes installedVersion: _host.version];
        }
    }
    
    NSView *boxContentView = _releaseNotesBoxView.contentView;
    assert(_releaseNotesSpinner != nil);
    [boxContentView addSubview:_releaseNotesView.view positioned:NSWindowBelow relativeTo:_releaseNotesSpinner];
    
    _releaseNotesView.view.frame = boxContentView.bounds;
    _releaseNotesView.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    
    [self adaptReleaseNotesAppearance];
}

- (void)windowDidLoad
{
    NSWindow *window = self.window;
    
    BOOL showReleaseNotes = [self showsReleaseNotes];
    if (showReleaseNotes) {
        window.frameAutosaveName = @"SUUpdateAlert";
    } else {
        // Update alert should not be resizable when no release notes are available
        window.styleMask &= ~NSWindowStyleMaskResizable;
    }

    if (_updateItem.informationOnlyUpdate) {
        [_installButton setTitle:SULocalizedStringFromTableInBundle(@"Learn More…", SPARKLE_TABLE, SUSparkleBundle(), @"Alternate title for 'Install Update' button when there's no download in RSS feed.")];
        [_installButton setAction:@selector(openInfoURL:)];
    }

    BOOL allowsAutomaticUpdates = _allowsAutomaticUpdates;
    
    if (showReleaseNotes) {
        [self displayReleaseNotesSpinner];
    } else {
        // When automatic updates aren't allowed we won't show the automatic install updates button
        // This button is removed later below
        if (allowsAutomaticUpdates) {
            NSLayoutConstraint *automaticallyInstallUpdatesButtonToDescriptionFieldConstraint = [NSLayoutConstraint constraintWithItem:_automaticallyInstallUpdatesButton attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:_descriptionField attribute:NSLayoutAttributeBottom multiplier:1.0 constant:8.0];
            
            [window.contentView addConstraint:automaticallyInstallUpdatesButtonToDescriptionFieldConstraint];
        }
        
        [_releaseNotesContainerView removeFromSuperview];
    }
    
    // NOTE: The code below for deciding what buttons to hide is complex! Due to array of feature configurations :)
    
    // When we show release notes, it looks ugly if the install buttons are not closer to the release notes view
    // However when we don't show release notes, it looks ugly if the install buttons are too close to the description field. Shrugs.
    if (!allowsAutomaticUpdates) {
        if (showReleaseNotes) {
            // Fix constraints so that buttons aren't far away from web view when we hide the automatic updates check box
            NSLayoutConstraint *skipButtonToReleaseNotesContainerConstraint = [NSLayoutConstraint constraintWithItem:_skipButton attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:_releaseNotesContainerView attribute:NSLayoutAttributeBottom multiplier:1.0 constant:12.0];
            
            [window.contentView addConstraint:skipButtonToReleaseNotesContainerConstraint];
        } else {
            NSLayoutConstraint *skipButtonToDescriptionConstraint = [NSLayoutConstraint constraintWithItem:_skipButton attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:_descriptionField attribute:NSLayoutAttributeBottom multiplier:1.0 constant:20.0];

            [window.contentView addConstraint:skipButtonToDescriptionConstraint];
        }
        [_automaticallyInstallUpdatesButton removeFromSuperview];
    }
    
    if (_state.stage == SPUUserUpdateStageInstalling) {
#if SPARKLE_COPY_LOCALIZATIONS
        NSBundle *sparkleBundle = SUSparkleBundle();
#endif
        
        // We're going to be relaunching pretty instantaneously
        _installButton.title = SULocalizedStringFromTableInBundle(@"Install and Relaunch", SPARKLE_TABLE, sparkleBundle, nil);
        
        // We should be explicit that the update will be installed on quit
        _laterButton.title = SULocalizedStringFromTableInBundle(@"Install on Quit", SPARKLE_TABLE, sparkleBundle, @"Alternate title for 'Remind Me Later' button when downloaded updates can be resumed");
    }

    if (_updateItem.criticalUpdate && !_updateItem.majorUpgrade) {
        _skipButton.hidden = YES;
        _laterButton.hidden = YES;
    }
    
    // Reminding user later doesn't make sense when automatic update checks are off
    if (![_host boolForKey:SUEnableAutomaticChecksKey]) {
        _laterButton.hidden = YES;
    }

    [window center];
}

- (void)windowDidBecomeKey:(NSNotification *)__unused note
{
    if (_didBecomeKeyBlock != NULL) {
        _didBecomeKeyBlock();
    }
}

- (BOOL)windowShouldClose:(NSNotification *) __unused note
{
    [self endWithSelection:SPUUserUpdateChoiceDismiss];
    return YES;
}

- (NSImage *)applicationIcon
{
    return [SUApplicationInfo bestIconForHost:_host];
}

- (NSString *)titleText
{
#if SPARKLE_COPY_LOCALIZATIONS
    NSBundle *sparkleBundle = SUSparkleBundle();
#endif
    
    if (_updateItem.criticalUpdate)
    {
        return [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"An important update to %@ is ready to install", SPARKLE_TABLE, sparkleBundle, nil), _host.name];
    }
    else if (_state.stage == SPUUserUpdateStageDownloaded || _state.stage == SPUUserUpdateStageInstalling)
    {
        return [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"A new version of %@ is ready to install!", SPARKLE_TABLE, sparkleBundle, nil), _host.name];
    }
    else
    {
        return [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"A new version of %@ is available!", SPARKLE_TABLE, sparkleBundle, nil), _host.name];
    }
}

- (NSString *)descriptionText
{
    NSString *updateItemDisplayVersion = [_updateItem displayVersionString];
    NSString *hostDisplayVersion = [_host displayVersion];
    
    if ([_versionDisplayer respondsToSelector:@selector(formatUpdateDisplayVersionFromUpdate:andBundleDisplayVersion:withBundleVersion:)]) {
        updateItemDisplayVersion = [_versionDisplayer formatUpdateDisplayVersionFromUpdate:_updateItem andBundleDisplayVersion:&hostDisplayVersion withBundleVersion:_host.version];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [_versionDisplayer formatVersion:&updateItemDisplayVersion andVersion:&hostDisplayVersion];
#pragma clang diagnostic pop
    }

    // We display a different summary depending on if it's an "info-only" item, or a "critical update" item, or if we've already downloaded the update and just need to relaunch
    NSString *finalString = nil;

#if SPARKLE_COPY_LOCALIZATIONS
    NSBundle *sparkleBundle = SUSparkleBundle();
#endif
    
    if (_updateItem.informationOnlyUpdate) {
        finalString = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%@ %@ is now available—you have %@. Would you like to learn more about this update on the web?", SPARKLE_TABLE, sparkleBundle, @"Description text for SUUpdateAlert when the update informational with no download."), _host.name, updateItemDisplayVersion, hostDisplayVersion];
    } else if (_updateItem.criticalUpdate) {
        if (_state.stage == SPUUserUpdateStageNotDownloaded) {
            finalString = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%@ %@ is now available—you have %@. This is an important update; would you like to download it now?", SPARKLE_TABLE, sparkleBundle, @"Description text for SUUpdateAlert when the critical update is downloadable."), _host.name, updateItemDisplayVersion, hostDisplayVersion];
        } else {
            finalString = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%1$@ %2$@ has been downloaded and is ready to use! This is an important update; would you like to install it and relaunch %1$@ now?", SPARKLE_TABLE, sparkleBundle, @"Description text for SUUpdateAlert when the critical update has already been downloaded and ready to install."), _host.name, updateItemDisplayVersion];
        }
    } else {
        if (_state.stage == SPUUserUpdateStageNotDownloaded) {
            finalString = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%@ %@ is now available—you have %@. Would you like to download it now?", SPARKLE_TABLE, sparkleBundle, @"Description text for SUUpdateAlert when the update is downloadable."), _host.name, updateItemDisplayVersion, hostDisplayVersion];
        } else {
            finalString = [NSString stringWithFormat:SULocalizedStringFromTableInBundle(@"%1$@ %2$@ has been downloaded and is ready to use! Would you like to install it and relaunch %1$@ now?", SPARKLE_TABLE, sparkleBundle, @"Description text for SUUpdateAlert when the update has already been downloaded and ready to install."), _host.name, updateItemDisplayVersion];
        }
    }
    return finalString;
}

- (NSTouchBar *)makeTouchBar
{
    NSTouchBar *touchBar = [[NSTouchBar alloc] init];
    touchBar.defaultItemIdentifiers = @[SUUpdateAlertTouchBarIndentifier,];
    touchBar.principalItemIdentifier = SUUpdateAlertTouchBarIndentifier;
    touchBar.delegate = self;
    return touchBar;
}

- (NSTouchBarItem *)touchBar:(NSTouchBar * __unused)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
    if ([identifier isEqualToString:SUUpdateAlertTouchBarIndentifier]) {
        NSCustomTouchBarItem* item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        item.viewController = [[SUTouchBarButtonGroup alloc] initByReferencingButtons:@[_installButton, _laterButton, _skipButton]];
        return item;
    }
    return nil;
}

@end

#endif
