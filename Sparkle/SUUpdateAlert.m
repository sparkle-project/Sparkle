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


@interface WebView ()

-(void)	setDrawsBackground: (BOOL)state;

@end

@interface SUUpdateAlert ()

@property (strong) SUAppcastItem *updateItem;
@property (strong) SUHost *host;

@property (strong) NSProgressIndicator *releaseNotesSpinner;
@property (assign) BOOL webViewFinishedLoading;

@property (weak) IBOutlet WebView *releaseNotesView;
@property (weak) IBOutlet NSTextField *descriptionField;
@property (weak) IBOutlet NSButton *installButton;
@property (weak) IBOutlet NSButton *skipButton;
@property (weak) IBOutlet NSButton *laterButton;

@end

@implementation SUUpdateAlert

@synthesize delegate;
@synthesize versionDisplayer;

@synthesize updateItem;
@synthesize host;

@synthesize releaseNotesSpinner;
@synthesize webViewFinishedLoading;

@synthesize releaseNotesView;
@synthesize descriptionField;
@synthesize installButton;
@synthesize skipButton;
@synthesize laterButton;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item host:(SUHost *)aHost
{
    self = [super initWithHost:host windowNibName:@"SUUpdateAlert"];
	if (self)
	{
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

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], [self.host bundlePath]]; }


- (void)endWithSelection:(SUUpdateAlertChoice)choice
{
    [self.releaseNotesView stopLoading:self];
    [self.releaseNotesView setFrameLoadDelegate:nil];
    [self.releaseNotesView setPolicyDelegate:nil];
    [self.releaseNotesView removeFromSuperview]; // Otherwise it gets sent Esc presses (why?!) and gets very confused.
    [self close];
    if ([self.delegate respondsToSelector:@selector(updateAlert:finishedWithChoice:)])
        [self.delegate updateAlert:self finishedWithChoice:choice];
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
    // Set the default font
    [self.releaseNotesView setPreferencesIdentifier:[SPARKLE_BUNDLE bundleIdentifier]];
    WebPreferences *prefs = [self.releaseNotesView preferences];
    NSString *familyName = [[NSFont systemFontOfSize:8] familyName];
    if ([familyName hasPrefix:@"."]) { // 10.9 returns ".Lucida Grande UI", which isn't a valid name for the WebView
        familyName = @"Lucida Grande";
    }
    [prefs setStandardFontFamily:familyName];
    [prefs setDefaultFontSize:(int)[NSFont systemFontSizeForControlSize:NSSmallControlSize]];
    [prefs setPlugInsEnabled:NO];
    [self.releaseNotesView setFrameLoadDelegate:self];
    [self.releaseNotesView setPolicyDelegate:self];

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
		if ([[self.updateItem releaseNotesURL] isFileURL])
		{
            [[self.releaseNotesView mainFrame] loadHTMLString:@"Release notes with file:// URLs are not supported for security reasons&mdash;Javascript would be able to read files on your file system." baseURL:nil];
		}
		else
		{
            [[self.releaseNotesView mainFrame] loadRequest:[NSURLRequest requestWithURL:[self.updateItem releaseNotesURL] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30]];
        }
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
    BOOL allowAutoUpdates = YES; // Defaults to YES.
    if ([self.host objectForInfoDictionaryKey:SUAllowsAutomaticUpdatesKey])
        allowAutoUpdates = [self.host boolForInfoDictionaryKey:SUAllowsAutomaticUpdatesKey];

    // Give delegate a chance to modify this choice:
    if (self.delegate && [self.delegate respondsToSelector:@selector(updateAlert:shouldAllowAutoUpdate:)])
        [self.delegate updateAlert:self shouldAllowAutoUpdate:&allowAutoUpdates];

    return allowAutoUpdates;
}

- (void)awakeFromNib
{
	NSString*	sizeStr = [self.host objectForInfoDictionaryKey:SUFixedHTMLDisplaySizeKey];

	if ([self.host isBackgroundApplication]) {
		[[self window] setLevel:NSFloatingWindowLevel];	// This means the window will float over all other apps, if our app is switched out ?! UK 2007-09-04
	}
	[[self window] setFrameAutosaveName: sizeStr ? @"" : @"SUUpdateAlertFrame"];

	// We're gonna do some frame magic to match the window's size to the description field and the presence of the release notes view.
	NSRect	frame = [[self window] frame];
	BOOL	showReleaseNotes = [self showsReleaseNotes];
	if (!showReleaseNotes) {
		// Resize the window to be appropriate for not having a huge release notes view.
		frame.size.height -= [self.releaseNotesView frame].size.height + 40; // Extra 40 is for the release notes label and margin.

		if ([self allowsAutomaticUpdates]) {
            frame.size.height += 10; // Make room for the check box.
		}

		// Hiding the resize handles is not enough on 10.5, you can still click
		//	where they would be, so we set the min/max sizes to be equal to
		//	inhibit resizing completely:
		[[self window] setShowsResizeIndicator: NO];
		[[self window] setMinSize: frame.size];
		[[self window] setMaxSize: frame.size];
	}
    else if (![self allowsAutomaticUpdates])
	{
		NSRect boxFrame = [[[self.releaseNotesView superview] superview] frame];
		boxFrame.origin.y -= 20;
		boxFrame.size.height += 20;
		[[[self.releaseNotesView superview] superview] setFrame:boxFrame];
	}

	if( [self.updateItem fileURL] == nil ) {
		[self.installButton setTitle: SULocalizedString( @"Learn More...", @"Alternate title for 'Install Update' button when there's no download in RSS feed." )];
		[self.installButton setAction: @selector(openInfoURL:)];
	}

	// Make sure button widths are OK:
	#define DISTANCE_BETWEEN_BUTTONS		3
	#define DISTANCE_BETWEEN_BUTTON_GROUPS	12

	CGFloat				minimumWindowWidth = [[self window] frame].size.width -NSMaxX([self.self.installButton frame]) +NSMinX([self.skipButton frame]);	// Distance between contents and left/right edge.
	NSDictionary*		attrs = @{NSFontAttributeName: [self.installButton font]};
	NSSize				titleSize = [[self.installButton title] sizeWithAttributes: attrs];
	titleSize.width += (16 + 8) * 2;	// 16 px for the end caps plus 8 px padding at each end or it'll look as ugly as calling -sizeToFit.
	NSRect				installBtnBox = [self.installButton frame];
	installBtnBox.origin.x += installBtnBox.size.width -titleSize.width;
	installBtnBox.size.width = titleSize.width;
	[self.installButton setFrame: installBtnBox];
	minimumWindowWidth += titleSize.width;

	titleSize = [[self.laterButton title] sizeWithAttributes: attrs];
	titleSize.width += (16 + 8) * 2;	// 16 px for the end caps plus 8 px padding at each end or it'll look as ugly as calling -sizeToFit.
	NSRect				laterBtnBox = [self.installButton frame];
	laterBtnBox.origin.x = installBtnBox.origin.x -DISTANCE_BETWEEN_BUTTONS -titleSize.width;
	laterBtnBox.size.width = titleSize.width;
	[self.laterButton setFrame: laterBtnBox];
	minimumWindowWidth += DISTANCE_BETWEEN_BUTTONS +titleSize.width;

	titleSize = [[self.skipButton title] sizeWithAttributes: attrs];
	titleSize.width += (16 + 8) * 2;	// 16 px for the end caps plus 8 px padding at each end or it'll look as ugly as calling -sizeToFit.
	NSRect				skipBtnBox = [self.skipButton frame];
	skipBtnBox.size.width = titleSize.width;
	[self.skipButton setFrame: skipBtnBox];
	minimumWindowWidth += DISTANCE_BETWEEN_BUTTON_GROUPS +titleSize.width;

	if( showReleaseNotes ) {
		if( sizeStr ) {
			NSSize		desiredSize = NSSizeFromString( sizeStr );
			NSSize		sizeDiff = NSZeroSize;
			// NSBox*		boxView = (NSBox*)[[releaseNotesView superview] superview];

			//[boxView setBorderType: NSNoBorder];
			[self.releaseNotesView setDrawsBackground: NO];

			sizeDiff.width = desiredSize.width -[self.releaseNotesView frame].size.width;
			sizeDiff.height = desiredSize.height -[self.releaseNotesView frame].size.height;
			frame.size.width += sizeDiff.width;
			frame.size.height += sizeDiff.height;

			// No resizing:
			[[self window] setShowsResizeIndicator:NO];
			[[self window] setMinSize:frame.size];
			[[self window] setMaxSize:frame.size];
		}
	}

	if (frame.size.width < minimumWindowWidth) {
		frame.size.width = minimumWindowWidth;
	}

	[[self window] setFrame: frame display: NO];
	[[self window] center];

	if (showReleaseNotes) {
		[self displayReleaseNotes];
	}

	[[[self.releaseNotesView superview] superview] setHidden: !showReleaseNotes];

}

-(BOOL)showsReleaseNotesText
{
	return( [self.host objectForInfoDictionaryKey:SUFixedHTMLDisplaySizeKey] == nil );
}


- (BOOL)windowShouldClose:(NSNotification *) __unused note
{
	[self endWithSelection:SURemindMeLaterChoice];
	return YES;
}

- (NSImage *)applicationIcon
{
    return [self.host icon];
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
    if (!self.versionDisplayer && [updateItemVersion isEqualToString:hostVersion] )
	{
        updateItemVersion = [updateItemVersion stringByAppendingFormat:@" (%@)", [self.updateItem versionString]];
        hostVersion = [hostVersion stringByAppendingFormat:@" (%@)", [self.host version]];
    }
	else {
        [self.versionDisplayer formatVersion:&updateItemVersion andVersion:&hostVersion];
    }
    return [NSString stringWithFormat:SULocalizedString(@"%@ %@ is now available--you have %@. Would you like to download it now?", nil), [self.host name], updateItemVersion, hostVersion];
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:frame
{
    if ([frame parentFrame] == nil) {
        self.webViewFinishedLoading = YES;
        [self.releaseNotesSpinner setHidden:YES];
        [sender display]; // necessary to prevent weird scroll bar artifacting
    }
}

- (void)webView:(WebView *)__unused sender decidePolicyForNavigationAction:(NSDictionary *)__unused actionInformation request:(NSURLRequest *)request frame:(WebFrame *)__unused frame decisionListener:(id<WebPolicyDecisionListener>)listener
{
    if (self.webViewFinishedLoading) {
        [[NSWorkspace sharedWorkspace] openURL:[request URL]];

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

@end
