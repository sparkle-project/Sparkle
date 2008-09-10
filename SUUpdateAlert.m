//
//  SUUpdateAlert.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUUpdateAlert.h"

#import "SUHost.h"
#import <WebKit/WebKit.h>

@implementation SUUpdateAlert

- (id)initWithAppcastItem:(SUAppcastItem *)item host:(SUHost *)aHost
{
	self = [super initWithHost:host windowNibName:@"SUUpdateAlert"];
	if (self)
	{
		host = [aHost retain];
		updateItem = [item retain];
		[self setShouldCascadeWindows:NO];
	}
	return self;
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], [host bundlePath]]; }

- (void)dealloc
{
	[updateItem release];
	[host release];
	[super dealloc];
}

- (void)endWithSelection:(SUUpdateAlertChoice)choice
{
	[releaseNotesView stopLoading:self];
	[releaseNotesView setFrameLoadDelegate:nil];
	[releaseNotesView setPolicyDelegate:nil];
	[self close];
	if ([delegate respondsToSelector:@selector(updateAlert:finishedWithChoice:)])
		[delegate updateAlert:self finishedWithChoice:choice];
}

- (IBAction)installUpdate:sender
{
	[self endWithSelection:SUInstallUpdateChoice];
}

- (IBAction)skipThisVersion:sender
{
	[self endWithSelection:SUSkipThisVersionChoice];
}

- (IBAction)remindMeLater:sender
{
	[self endWithSelection:SURemindMeLaterChoice];
}

- (void)displayReleaseNotes
{
	// Set the default font, but avoid polluting the standard preferences.
	WebPreferences *preferences = [NSKeyedUnarchiver unarchiveObjectWithData:[NSKeyedArchiver archivedDataWithRootObject:[WebPreferences standardPreferences]]];
    [preferences setStandardFontFamily:[[NSFont systemFontOfSize:8] familyName]];
	[preferences setDefaultFontSize:(int)[NSFont systemFontSizeForControlSize:NSSmallControlSize]];
	[releaseNotesView setPreferences:preferences];
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
			[[releaseNotesView mainFrame] loadRequest:[NSURLRequest requestWithURL:[updateItem releaseNotesURL] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30]];
		}
	}
	else
	{
		[[releaseNotesView mainFrame] loadHTMLString:[updateItem itemDescription] baseURL:nil];
	}	
}

- (BOOL)showsReleaseNotes
{
	NSNumber *shouldShowReleaseNotes = [host objectForInfoDictionaryKey:SUShowReleaseNotesKey];
	if (shouldShowReleaseNotes == nil)
		return YES; // defaults to YES
	else
		return [shouldShowReleaseNotes boolValue];
}

- (BOOL)allowsAutomaticUpdates
{
	if (![host objectForInfoDictionaryKey:SUAllowsAutomaticUpdatesKey])
		return YES; // defaults to YES
	return [host boolForInfoDictionaryKey:SUAllowsAutomaticUpdatesKey];
}

- (void)awakeFromNib
{	
	[[self window] setLevel:NSFloatingWindowLevel];
		
	// We're gonna do some frame magic to match the window's size to the description field and the presence of the release notes view.
	NSRect frame = [[self window] frame];
	
	if (![self showsReleaseNotes])
	{
		// Resize the window to be appropriate for not having a huge release notes view.
		frame.size.height -= [releaseNotesView frame].size.height + 40; // Extra 40 is for the release notes label and margin.
		[[self window] setShowsResizeIndicator:NO];
	}
	
	if (![self allowsAutomaticUpdates])
	{
		NSRect boxFrame = [[[releaseNotesView superview] superview] frame];
		boxFrame.origin.y -= 20;
		boxFrame.size.height += 20;
		[[[releaseNotesView superview] superview] setFrame:boxFrame];
	}
	
	[[self window] setFrame:frame display:NO];
	[[self window] center];
	
	if ([self showsReleaseNotes])
	{
		[self displayReleaseNotes];
	}
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
    if ([updateItemVersion isEqualToString:hostVersion])
	{
        updateItemVersion = [updateItemVersion stringByAppendingFormat:@" (%@)", [updateItem versionString]];
        hostVersion = [hostVersion stringByAppendingFormat:@" (%@)", [host version]];
    }
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
    if (webViewFinishedLoading == YES) {
        [[NSWorkspace sharedWorkspace] openURL:[request URL]];
		
        [listener ignore];
    }    
    else {
        [listener use];
    }
}

- (void)setDelegate:del
{
	delegate = del;
}

@end
