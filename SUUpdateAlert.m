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
#import "SUXPCURLDownload.h"

@interface WebView (SUTenFiveProperty)

-(void)	setDrawsBackground: (BOOL)state;

@end


@implementation SUUpdateAlert

- (id)initWithAppcastItem:(SUAppcastItem *)item host:(SUHost *)aHost
{
	self = [super initWithHost:host windowNibName:@"SUUpdateAlert"];
	if (self)
	{
		host = [aHost retain];
		updateItem = [item retain];
		[self setShouldCascadeWindows:NO];
		
		// Alex: This dummy line makes sure that the binary is linked against WebKit.
		// The SUUpdateAlert.xib file contains a WebView and if we don't link against WebKit,
		// we will get a runtime crash when decoding the NIB. It is better to get a link error.
		[WebView MIMETypesShownAsHTML];
	}
	return self;
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], [host bundlePath]]; }

- (void)dealloc
{
	[updateItem release];
	[host release];
    [releaseNotesDownloader release];
    [downloadedReleaseNotesPath release];
    
	[super dealloc];
}

- (void)setVersionDisplayer: (id<SUVersionDisplay>)disp
{
	versionDisplayer = disp;
}

- (void)endWithSelection:(SUUpdateAlertChoice)choice
{
	[releaseNotesView stopLoading:self];
	[releaseNotesView setFrameLoadDelegate:nil];
	[releaseNotesView setPolicyDelegate:nil];
	[releaseNotesView removeFromSuperview]; // Otherwise it gets sent Esc presses (why?!) and gets very confused.
	[self close];
	if ([delegate respondsToSelector:@selector(updateAlert:finishedWithChoice:)])
		[delegate updateAlert:self finishedWithChoice:choice];
}

- (IBAction)installUpdate: (id)sender
{
	[self endWithSelection:SUInstallUpdateChoice];
}

- (IBAction)openInfoURL: (id)sender
{
	[self endWithSelection:SUOpenInfoURLChoice];
}

- (IBAction)skipThisVersion: (id)sender
{
	[self endWithSelection:SUSkipThisVersionChoice];
}

- (IBAction)remindMeLater: (id)sender
{
	[self endWithSelection:SURemindMeLaterChoice];
}

- (void)displayReleaseNotes
{
	// Set the default font	
	[releaseNotesView setPreferencesIdentifier:[SPARKLE_BUNDLE bundleIdentifier]];
	[[releaseNotesView preferences] setStandardFontFamily:[[NSFont systemFontOfSize:8] familyName]];
	[[releaseNotesView preferences] setDefaultFontSize:(int)[NSFont systemFontSizeForControlSize:NSSmallControlSize]];
	[releaseNotesView setFrameLoadDelegate:self];
	[releaseNotesView setPolicyDelegate:self];
	
	// Stick a nice big spinner in the middle of the web view until the page is loaded.
	NSRect frame = [[releaseNotesView superview] frame];
	releaseNotesSpinner = [[[NSProgressIndicator alloc] initWithFrame:NSMakeRect(NSMidX(frame)-16, NSMidY(frame)-16, 32, 32)] autorelease];
	[releaseNotesSpinner setStyle:NSProgressIndicatorSpinningStyle];
	[releaseNotesSpinner startAnimation:self];
	webViewFinishedLoading = NO;
	[[releaseNotesView superview] addSubview:releaseNotesSpinner];
	
	// If there's a release notes URL, load it; otherwise, just stick the contents of the description into the web view.
	if ([updateItem releaseNotesURL])
	{
		if ([[updateItem releaseNotesURL] isFileURL])
		{
			[[releaseNotesView mainFrame] loadHTMLString:@"Release notes with file:// URLs are not supported for security reasons&mdash;Javascript would be able to read files on your file system." baseURL:nil];
		}
		else
		{
            NSURLRequest *request = [NSURLRequest requestWithURL:[updateItem releaseNotesURL] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30];
            if ([SUUpdater shouldUseXPC]) {
                releaseNotesDownloader = (NSURLDownload *)[[SUXPCURLDownload alloc] initWithRequest:request delegate:self];
            } else {
                [[releaseNotesView mainFrame] loadRequest:request];
            }
		}
	}
	else
	{
		[[releaseNotesView mainFrame] loadHTMLString:[updateItem itemDescription] baseURL:nil];
	}	
}

- (void)download:(NSURLDownload *)aDownload didCreateDestination:(NSString *)path
{
    [downloadedReleaseNotesPath release];
    downloadedReleaseNotesPath = [path copy];
}

- (void)downloadDidFinish:(NSURLDownload *)aDownload
{
    NSString *s = [NSString stringWithContentsOfFile:downloadedReleaseNotesPath encoding:NSUTF8StringEncoding error:nil];
    [[releaseNotesView mainFrame] loadHTMLString:s baseURL:nil];
}

- (BOOL)showsReleaseNotes
{
	NSNumber *shouldShowReleaseNotes = [host objectForInfoDictionaryKey:SUShowReleaseNotesKey];
	if (shouldShowReleaseNotes == nil)
	{
		// UK 2007-09-18: Don't show release notes if RSS item contains no description and no release notes URL:
		return( ([updateItem itemDescription] != nil
			&& [[[updateItem itemDescription] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]] length] > 0)
			|| [updateItem releaseNotesURL] != nil );
	}
	else
		return [shouldShowReleaseNotes boolValue];
}

- (BOOL)allowsAutomaticUpdates
{
	BOOL		allowAutoUpdates = YES;	// Defaults to YES.
	if( [host objectForInfoDictionaryKey:SUAllowsAutomaticUpdatesKey] )
		allowAutoUpdates = [host boolForInfoDictionaryKey: SUAllowsAutomaticUpdatesKey];
	
	// UK 2007-08-31: Give delegate a chance to modify this choice:
	if( delegate && [delegate respondsToSelector: @selector(updateAlert:shouldAllowAutoUpdate:)] )
		[delegate updateAlert: self shouldAllowAutoUpdate: &allowAutoUpdates];
	
	return allowAutoUpdates;
}

- (void)awakeFromNib
{	
	NSString*	sizeStr = [host objectForInfoDictionaryKey:SUFixedHTMLDisplaySizeKey];

	if( [host isBackgroundApplication] )
		[[self window] setLevel:NSFloatingWindowLevel];	// This means the window will float over all other apps, if our app is switched out ?! UK 2007-09-04
	[[self window] setFrameAutosaveName: sizeStr ? @"" : @"SUUpdateAlertFrame"];
		
	// We're gonna do some frame magic to match the window's size to the description field and the presence of the release notes view.
	NSRect	frame = [[self window] frame];
	BOOL	showReleaseNotes = [self showsReleaseNotes];	// UK 2007-09-18
	if (!showReleaseNotes)	// UK 2007-09-18
	{
		// Resize the window to be appropriate for not having a huge release notes view.
		frame.size.height -= [releaseNotesView frame].size.height + 40; // Extra 40 is for the release notes label and margin.
        
        if ([self allowsAutomaticUpdates])
            frame.size.height += 10; // Make room for the check box.
		
		// Hiding the resize handles is not enough on 10.5, you can still click
		//	where they would be, so we set the min/max sizes to be equal to
		//	inhibit resizing completely:
		[[self window] setShowsResizeIndicator: NO];
		[[self window] setMinSize: frame.size];
		[[self window] setMaxSize: frame.size];
	}
    else if (![self allowsAutomaticUpdates])
	{
		NSRect boxFrame = [[[releaseNotesView superview] superview] frame];
		boxFrame.origin.y -= 20;
		boxFrame.size.height += 20;
		[[[releaseNotesView superview] superview] setFrame:boxFrame];
	}
		
	if( [updateItem fileURL] == nil )	// UK 2007-08-31 (whole if clause)
	{
		[installButton setTitle: SULocalizedString( @"Learn More...", @"Alternate title for 'Install Update' button when there's no download in RSS feed." )];
		[installButton setAction: @selector(openInfoURL:)];
	}
	
	// Make sure button widths are OK:
	#define DISTANCE_BETWEEN_BUTTONS		3
	#define DISTANCE_BETWEEN_BUTTON_GROUPS	12
	
	CGFloat				minimumWindowWidth = [[self window] frame].size.width -NSMaxX([installButton frame]) +NSMinX([skipButton frame]);	// Distance between contents and left/right edge.
	NSDictionary*		attrs = [NSDictionary dictionaryWithObjectsAndKeys: [installButton font], NSFontAttributeName, nil];
	NSSize				titleSize = [[installButton title] sizeWithAttributes: attrs];
	titleSize.width += (16 + 8) * 2;	// 16 px for the end caps plus 8 px padding at each end or it'll look as ugly as calling -sizeToFit.
	NSRect				installBtnBox = [installButton frame];
	installBtnBox.origin.x += installBtnBox.size.width -titleSize.width;
	installBtnBox.size.width = titleSize.width;
	[installButton setFrame: installBtnBox];
	minimumWindowWidth += titleSize.width;
	
	titleSize = [[laterButton title] sizeWithAttributes: attrs];
	titleSize.width += (16 + 8) * 2;	// 16 px for the end caps plus 8 px padding at each end or it'll look as ugly as calling -sizeToFit.
	NSRect				laterBtnBox = [installButton frame];
	laterBtnBox.origin.x = installBtnBox.origin.x -DISTANCE_BETWEEN_BUTTONS -titleSize.width;
	laterBtnBox.size.width = titleSize.width;
	[laterButton setFrame: laterBtnBox];
	minimumWindowWidth += DISTANCE_BETWEEN_BUTTONS +titleSize.width;
	
	titleSize = [[skipButton title] sizeWithAttributes: attrs];
	titleSize.width += (16 + 8) * 2;	// 16 px for the end caps plus 8 px padding at each end or it'll look as ugly as calling -sizeToFit.
	NSRect				skipBtnBox = [skipButton frame];
	skipBtnBox.size.width = titleSize.width;
	[skipButton setFrame: skipBtnBox];
	minimumWindowWidth += DISTANCE_BETWEEN_BUTTON_GROUPS +titleSize.width;
	
	if( showReleaseNotes )	// UK 2007-09-18 (whole block)
	{
		if( sizeStr )
		{
			NSSize		desiredSize = NSSizeFromString( sizeStr );
			NSSize		sizeDiff = NSZeroSize;
			// NSBox*		boxView = (NSBox*)[[releaseNotesView superview] superview];
			
			//[boxView setBorderType: NSNoBorder];
			[releaseNotesView setDrawsBackground: NO];
			
			sizeDiff.width = desiredSize.width -[releaseNotesView frame].size.width;
			sizeDiff.height = desiredSize.height -[releaseNotesView frame].size.height;
			frame.size.width += sizeDiff.width;
			frame.size.height += sizeDiff.height;
			
			// No resizing:
			[[self window] setShowsResizeIndicator:NO];
			[[self window] setMinSize:frame.size];
			[[self window] setMaxSize:frame.size];
		}
	}
	
	if( frame.size.width < minimumWindowWidth )
		frame.size.width = minimumWindowWidth;

	[[self window] setFrame: frame display: NO];
	[[self window] center];
	
	if (showReleaseNotes)	// UK 2007-09-18
	{
		[self displayReleaseNotes];
	}
	
	[[[releaseNotesView superview] superview] setHidden: !showReleaseNotes];	// UK 2007-09-18

}

-(BOOL)showsReleaseNotesText
{
	return( [host objectForInfoDictionaryKey:SUFixedHTMLDisplaySizeKey] == nil );
}


- (BOOL)windowShouldClose:note
{
	[self endWithSelection:SURemindMeLaterChoice];
	return YES;
}

- (NSImage *)applicationIcon
{
	return [host icon];
}

- (NSString *)titleText
{
	return [NSString stringWithFormat:SULocalizedString(@"A new version of %@ is available!", nil), [host name]];
}

- (NSString *)descriptionText
{
	NSString *updateItemVersion = [updateItem displayVersionString];
    NSString *hostVersion = [host displayVersion];
	// Display more info if the version strings are the same; useful for betas.
    if( !versionDisplayer && [updateItemVersion isEqualToString:hostVersion] )
	{
        updateItemVersion = [updateItemVersion stringByAppendingFormat:@" (%@)", [updateItem versionString]];
        hostVersion = [hostVersion stringByAppendingFormat:@" (%@)", [host version]];
    }
	else
		[versionDisplayer formatVersion: &updateItemVersion andVersion: &hostVersion];
    return [NSString stringWithFormat:SULocalizedString(@"%@ %@ is now available--you have %@. Would you like to download it now?", nil), [host name], updateItemVersion, hostVersion];
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:frame
{
    if ([frame parentFrame] == nil) {
        webViewFinishedLoading = YES;
		[releaseNotesSpinner setHidden:YES];
		[sender display]; // necessary to prevent weird scroll bar artifacting
    }
}

- (void)webView:sender decidePolicyForNavigationAction:(NSDictionary *)actionInformation request:(NSURLRequest *)request frame:frame decisionListener:listener
{
    if (webViewFinishedLoading) {
        [[NSWorkspace sharedWorkspace] openURL:[request URL]];
		
        [listener ignore];
    }    
    else {
        [listener use];
    }
}

// Clean up the contextual menu.
- (NSArray *)webView:(WebView *)sender contextMenuItemsForElement:(NSDictionary *)element defaultMenuItems:(NSArray *)defaultMenuItems
{
	NSMutableArray *webViewMenuItems = [[defaultMenuItems mutableCopy] autorelease];
	
	if (webViewMenuItems)
	{
		NSEnumerator *itemEnumerator = [defaultMenuItems objectEnumerator];
		NSMenuItem *menuItem = nil;
		while ((menuItem = [itemEnumerator nextObject]))
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
					[webViewMenuItems removeObjectIdenticalTo: menuItem];
			}
		}
	}
	
	return webViewMenuItems;
}

- (void)setDelegate:del
{
	delegate = del;
}

@end
