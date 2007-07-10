//
//  SUUpdateAlert.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUUpdateAlert.h"
#import "SUAppcastItem.h"
#import "SUUtilities.h"
#import <WebKit/WebKit.h>

@implementation SUUpdateAlert

- initWithAppcastItem:(SUAppcastItem *)item
{
	NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"SUUpdateAlert" ofType:@"nib"];
	if (!path) // slight hack to resolve issues with running with in configurations
	{
		NSBundle *current = [NSBundle bundleForClass:[self class]];
		NSString *frameworkPath = [[[NSBundle mainBundle] sharedFrameworksPath] stringByAppendingFormat:@"/Sparkle.framework", [current bundleIdentifier]];
		NSBundle *framework = [NSBundle bundleWithPath:frameworkPath];
		path = [framework pathForResource:@"SUUpdateAlert" ofType:@"nib"];
	}
	
	[super initWithWindowNibPath:path owner:self];
	
	updateItem = [item retain];
	[self setShouldCascadeWindows:NO];
	
	return self;
}

- (void)dealloc
{
	[updateItem release];
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
		[[releaseNotesView mainFrame] loadRequest:[NSURLRequest requestWithURL:[updateItem releaseNotesURL] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:30]];
	}
	else
	{
		[[releaseNotesView mainFrame] loadHTMLString:[updateItem description] baseURL:nil];
	}	
}

- (BOOL)showsReleaseNotes
{
	if (!SUInfoValueForKey(SUShowReleaseNotesKey)) { return YES; } // defaults to YES
	return [SUInfoValueForKey(SUShowReleaseNotesKey) boolValue];
}

- (BOOL)allowsAutomaticUpdates
{
	if (!SUInfoValueForKey(SUExpectsDSASignatureKey)) { return NO; } // automatic updating requires DSA-signed updates
	if (!SUInfoValueForKey(SUAllowsAutomaticUpdatesKey)) { return YES; } // defaults to YES
	return [SUInfoValueForKey(SUAllowsAutomaticUpdatesKey) boolValue];
}

- (void)awakeFromNib
{	
	[[self window] setLevel:NSFloatingWindowLevel];
	[[self window] setFrameAutosaveName:@"SUUpdateAlertFrame"];
		
	// We're gonna do some frame magic to match the window's size to the description field and the presence of the release notes view.
	NSRect frame = [[self window] frame];
	
	if (![self showsReleaseNotes])
	{
		// Resize the window to be appropriate for not having a huge release notes view.
		frame.size.height -= [releaseNotesView frame].size.height;
		// No resizing!
		[[self window] setShowsResizeIndicator:NO];
		[[self window] setMinSize:frame.size];
		[[self window] setMaxSize:frame.size];
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
	return [NSImage imageNamed:@"NSApplicationIcon"];
}

- (NSString *)titleText
{
	return [NSString stringWithFormat:SULocalizedString(@"A new version of %@ is available!", nil), SUHostAppDisplayName()];
}

- (NSString *)descriptionText
{
	return [NSString stringWithFormat:SULocalizedString(@"%@ %@ is now available (you have %@). Would you like to download it now?", nil), SUHostAppDisplayName(), [updateItem versionString], SUHostAppVersionString()];	
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
