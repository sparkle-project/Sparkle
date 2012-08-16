//
//  SUPasswordPrompt.m
//  Sparkle
//
//  Created by rudy on 8/18/09.
//  Copyright 2009 Ambrosia Software, Inc.. All rights reserved.
//

#import "SUPasswordPrompt.h"


@implementation SUPasswordPrompt

- (id)initWithHost:(SUHost *)aHost
{
	self = [super initWithHost:aHost windowNibName:@"SUPasswordPrompt"];
	if (self)
	{
		[self setName:[aHost name]];
		[self setIcon:[aHost icon]];
		mPassword = nil;
		[self setShouldCascadeWindows:NO];
	}
	return self;
}

- (void)awakeFromNib
{
	[mIconView setImage:[self icon]];
}

- (void)setName:(NSString*)name
{
	[mName release];
	mName = [name retain];
}

- (NSString*)name
{
	return mName;
}

- (void)setIcon:(NSImage*)icon
{
	[mIcon release];
	mIcon = [icon retain];
}

- (NSImage*)icon
{
	return mIcon;
}

- (NSString *)password
{
	return mPassword;
}

- (void)setPassword:(NSString*)password
{
	[mPassword release];
	mPassword = [password retain];
}

- (NSInteger)run
{
	//modally run a password prompt
	NSInteger result = [NSApp runModalForWindow:[self window]];
	if(result)
		[self setPassword:[mPasswordField stringValue]];
	return result;
}

- (IBAction)accept:(id)sender
{
	[[self window] orderOut:self];
	[NSApp stopModalWithCode:1];
}

- (IBAction)cancel:(id)sender
{
	[[self window] orderOut:self];
	[NSApp stopModalWithCode:0];
}

@end
