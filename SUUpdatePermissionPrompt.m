//
//  SUUpdatePermissionPrompt.m
//  Sparkle
//
//  Created by Andy Matuschak on 1/24/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUpdatePermissionPrompt.h"


@implementation SUUpdatePermissionPrompt

- (BOOL)shouldAskAboutProfile
{
	return [[hostBundle objectForInfoDictionaryKey:SUEnableSystemProfilingKey] boolValue];
}

- (id)initWithHostBundle:(NSBundle *)hb delegate:(id)d
{
	self = [super initWithHostBundle:hb windowNibName:@"SUUpdatePermissionPrompt"];
	if (self)
	{
		hostBundle = [hb retain];
		delegate = [d retain];
		isShowingMoreInfo = NO;
		shouldSendProfile = [self shouldAskAboutProfile];
		[self setShouldCascadeWindows:NO];
	}
	return self;
}

+ (void)promptWithHostBundle:(NSBundle *)hb delegate:(id)d
{
	id prompt = [[[self class] alloc] initWithHostBundle:hb delegate:d];
	[NSApp runModalForWindow:[prompt window]];
}

- (void)awakeFromNib
{
	if (![self shouldAskAboutProfile])
	{
		NSRect frame = [[self window] frame];
		frame.size.height -= [moreInfoButton frame].size.height;
		[[self window] setFrame:frame display:YES];
	}
}

- (void)dealloc
{
	[hostBundle release];
	[super dealloc];
}

- (NSImage *)icon
{
	return [hostBundle icon];
}

- (NSString *)promptDescription
{
	return [NSString stringWithFormat:SULocalizedString(@"Should %1$@ automatically check for updates? You can always check for updates manually from the %1$@ menu.", nil), [hostBundle name]];
}

- (NSArray *)systemProfileInformationArray
{
	return [[SUSystemProfiler sharedSystemProfiler] systemProfileArrayForHostBundle:hostBundle];
}

- (IBAction)toggleMoreInfo:(id)sender
{
	[self willChangeValueForKey:@"isShowingMoreInfo"];
	isShowingMoreInfo = !isShowingMoreInfo;
	[self didChangeValueForKey:@"isShowingMoreInfo"];
	
	NSView *contentView = [[self window] contentView];
	NSRect contentViewFrame = [contentView frame];
	NSRect windowFrame = [[self window] frame];
	
	NSRect profileMoreInfoViewFrame = [moreInfoView frame];
	NSRect profileMoreInfoButtonFrame = [moreInfoButton frame];
	NSRect descriptionFrame = [descriptionTextField frame];
	
	if (isShowingMoreInfo)
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
	[moreInfoView setHidden:(!isShowingMoreInfo)];
}

- (IBAction)finishPrompt:(id)sender
{
	if (![delegate respondsToSelector:@selector(updatePermissionPromptFinishedWithResult:)])
		[NSException raise:@"SUInvalidDelegate" format:@"SUUpdatePermissionPrompt's delegate (%@) doesn't respond to updatePermissionPromptFinishedWithResult:!", delegate];
	[[SUUserDefaults standardUserDefaults] setBool:shouldSendProfile forKey:SUSendProfileInfoKey];
	[delegate updatePermissionPromptFinishedWithResult:([sender tag] == 1 ? SUAutomaticallyCheck : SUDoNotAutomaticallyCheck)];
	[[self window] close];
	[NSApp stopModal];
	[self autorelease];
}

@end
