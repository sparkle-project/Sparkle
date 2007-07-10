//
//  SUStatusController.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/14/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUStatusController.h"
#import "SUUtilities.h"

@implementation SUStatusController

- init
{
	NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"SUStatus" ofType:@"nib"];
	if (!path) // slight hack to resolve issues with running in debug configurations
	{
		NSBundle *current = [NSBundle bundleForClass:[self class]];
		NSString *frameworkPath = [[[NSBundle mainBundle] sharedFrameworksPath] stringByAppendingFormat:@"/Sparkle.framework", [current bundleIdentifier]];
		NSBundle *framework = [NSBundle bundleWithPath:frameworkPath];
		path = [framework pathForResource:@"SUStatus" ofType:@"nib"];
	}
	[super initWithWindowNibPath:path owner:self];
	[self setShouldCascadeWindows:NO];
	return self;
}

- (void)dealloc
{
	[title release];
	[statusText release];
	[buttonTitle release];
	[super dealloc];
}

- (void)awakeFromNib
{
	[[self window] center];
	[[self window] setFrameAutosaveName:@"SUStatusFrame"];
}

- (NSString *)windowTitle
{
	return [NSString stringWithFormat:SULocalizedString(@"Updating %@", nil), SUHostAppDisplayName()];
}

- (NSImage *)applicationIcon
{
	return [NSImage imageNamed:@"NSApplicationIcon"];
}

- (void)beginActionWithTitle:(NSString *)aTitle maxProgressValue:(double)aMaxProgressValue statusText:(NSString *)aStatusText
{
	[self willChangeValueForKey:@"title"];
	title = [aTitle copy];
	[self didChangeValueForKey:@"title"];
	
	[self setMaxProgressValue:aMaxProgressValue];
	[self setStatusText:aStatusText];
}

- (void)setButtonTitle:(NSString *)aButtonTitle target:target action:(SEL)action isDefault:(BOOL)isDefault
{
	[self willChangeValueForKey:@"buttonTitle"];
	buttonTitle = [aButtonTitle copy];
	[self didChangeValueForKey:@"buttonTitle"];	
	
	[actionButton sizeToFit];
	// Except we're going to add 15 px for padding.
	[actionButton setFrameSize:NSMakeSize([actionButton frame].size.width + 15, [actionButton frame].size.height)];
	// Now we have to move it over so that it's always 15px from the side of the window.
	[actionButton setFrameOrigin:NSMakePoint([[self window] frame].size.width - 15 - [actionButton frame].size.width, [actionButton frame].origin.y)];	
	// Redisplay superview to clean up artifacts
	[[actionButton superview] display];
	
	[actionButton setTarget:target];
	[actionButton setAction:action];
	[actionButton setKeyEquivalent:isDefault ? @"\r" : @""];
}

- (void)setButtonEnabled:(BOOL)enabled
{
	[actionButton setEnabled:enabled];
}

- (double)progressValue
{
	return progressValue;
}

- (void)setProgressValue:(double)value
{
	[self willChangeValueForKey:@"progressValue"];
	progressValue = value;
	[self didChangeValueForKey:@"progressValue"];	
}

- (double)maxProgressValue
{
	return maxProgressValue;
}

- (void)setMaxProgressValue:(double)value
{
	[self willChangeValueForKey:@"maxProgressValue"];
	maxProgressValue = value;
	[self didChangeValueForKey:@"maxProgressValue"];
	[self setProgressValue:0];
}

- (void)setStatusText:(NSString *)aStatusText
{
	[self willChangeValueForKey:@"statusText"];
	statusText = [aStatusText copy];
	[self didChangeValueForKey:@"statusText"];	
}

@end
