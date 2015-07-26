//
//  SUUpdatePermissionPrompt.m
//  Sparkle
//
//  Created by Andy Matuschak on 1/24/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUpdatePermissionPrompt.h"

#import "SUHost.h"
#import "SUConstants.h"

@interface SUUpdatePermissionPrompt ()
@property BOOL isShowingMoreInfo, shouldSendProfile;
@end

@implementation SUUpdatePermissionPrompt

@synthesize isShowingMoreInfo = _isShowingMoreInfo, shouldSendProfile = _shouldSendProfile;

- (BOOL)shouldAskAboutProfile
{
	return [[host objectForInfoDictionaryKey:SUEnableSystemProfilingKey] boolValue];
}

- (instancetype)initWithHost:(SUHost *)aHost systemProfile:(NSArray *)profile delegate:(id<SUUpdatePermissionPromptDelegate>)d
{
	self = [super initWithHost:aHost windowNibName:@"SUUpdatePermissionPrompt"];
	if (self)
	{
		host = [aHost retain];
		delegate = d;
		self.isShowingMoreInfo = NO;
		self.shouldSendProfile = [self shouldAskAboutProfile];
		systemProfileInformationArray = [profile retain];
		[self setShouldCascadeWindows:NO];
	}
	return self;
}

+ (void)promptWithHost:(SUHost *)aHost systemProfile:(NSArray *)profile delegate:(id <SUUpdatePermissionPromptDelegate>)d
{
	// If this is a background application we need to focus it in order to bring the prompt
	// to the user's attention. Otherwise the prompt would be hidden behind other applications and
	// the user would not know why the application was paused.
	if ([aHost isBackgroundApplication]) { [[NSApplication sharedApplication] activateIgnoringOtherApps:YES]; }

	SUUpdatePermissionPrompt *prompt = [[[[self class] alloc] initWithHost:aHost systemProfile:profile delegate:d] autorelease];
	[NSApp runModalForWindow:[prompt window]];
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], [host bundlePath]]; }

- (void)awakeFromNib
{
	if (![self shouldAskAboutProfile])
	{
		NSRect frame = [[self window] frame];
		frame.size.height -= [moreInfoButton frame].size.height;
		[[self window] setFrame:frame display:YES];
	} else {
        // Set the table view's delegate so we can disable row selection.
        [profileTableView setDelegate:(id)self];
    }
}

- (BOOL)tableView:(NSTableView *) __unused tableView shouldSelectRow:(NSInteger) __unused row { return NO; }

- (void)dealloc
{
	[host release];
	[systemProfileInformationArray release];
	[super dealloc];
}

- (NSImage *)icon
{
	return [host icon];
}

- (NSString *)promptDescription
{
	return [NSString stringWithFormat:SULocalizedString(@"Should %1$@ automatically check for updates? You can always check for updates manually from the %1$@ menu.", nil), [host name]];
}

- (IBAction)toggleMoreInfo:(id) __unused sender
{
	self.isShowingMoreInfo = !_isShowingMoreInfo;

	NSView *contentView = [[self window] contentView];
	NSRect contentViewFrame = [contentView frame];
	NSRect windowFrame = [[self window] frame];

	NSRect profileMoreInfoViewFrame = [moreInfoView frame];
	NSRect profileMoreInfoButtonFrame = [moreInfoButton frame];
	NSRect descriptionFrame = [descriptionTextField frame];

	if (_isShowingMoreInfo)
	{
		// Add the subview
		contentViewFrame.size.height += profileMoreInfoViewFrame.size.height;
		profileMoreInfoViewFrame.origin.y = profileMoreInfoButtonFrame.origin.y - profileMoreInfoViewFrame.size.height;
		profileMoreInfoViewFrame.origin.x = descriptionFrame.origin.x;
		profileMoreInfoViewFrame.size.width = descriptionFrame.size.width;

		windowFrame.size.height += profileMoreInfoViewFrame.size.height;
		windowFrame.origin.y -= profileMoreInfoViewFrame.size.height;

		[moreInfoView setFrame:profileMoreInfoViewFrame];
		[moreInfoView setHidden:YES];
		[contentView addSubview:moreInfoView
					 positioned:NSWindowBelow
					 relativeTo:moreInfoButton];
	} else {
		// Remove the subview
		[moreInfoView setHidden:NO];
		[moreInfoView removeFromSuperview];
		contentViewFrame.size.height -= profileMoreInfoViewFrame.size.height;

		windowFrame.size.height -= profileMoreInfoViewFrame.size.height;
		windowFrame.origin.y += profileMoreInfoViewFrame.size.height;
	}
	[[self window] setFrame:windowFrame display:YES animate:YES];
	[contentView setFrame:contentViewFrame];
	[contentView setNeedsDisplay:YES];
	[moreInfoView setHidden:(!_isShowingMoreInfo)];
}

- (IBAction)finishPrompt:(id)sender
{
	if (![delegate respondsToSelector:@selector(updatePermissionPromptFinishedWithResult:)]) {
		[NSException raise:@"SUInvalidDelegate" format:@"SUUpdatePermissionPrompt's delegate (%@) doesn't respond to updatePermissionPromptFinishedWithResult:!", delegate];
	}
	[host setBool:_shouldSendProfile forUserDefaultsKey:SUSendProfileInfoKey];
	[delegate updatePermissionPromptFinishedWithResult:([sender tag] == 1 ? SUAutomaticallyCheck : SUDoNotAutomaticallyCheck)];
	[[self window] close];
	[NSApp stopModal];
}

@end
