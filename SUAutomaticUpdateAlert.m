//
//  SUAutomaticUpdateAlert.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/18/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUAutomaticUpdateAlert.h"
#import "SUUtilities.h"
#import "SUAppcastItem.h"

@implementation SUAutomaticUpdateAlert

- initWithAppcastItem:(SUAppcastItem *)item
{
	NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"SUAutomaticUpdateAlert" ofType:@"nib"];
	if (!path) // slight hack to resolve issues with running with in configurations
	{
		NSBundle *current = [NSBundle bundleForClass:[self class]];
		NSString *frameworkPath = [[[NSBundle mainBundle] sharedFrameworksPath] stringByAppendingFormat:@"/Sparkle.framework", [current bundleIdentifier]];
		NSBundle *framework = [NSBundle bundleWithPath:frameworkPath];
		path = [framework pathForResource:@"SUAutomaticUpdateAlert" ofType:@"nib"];
	}
	
	[super initWithWindowNibPath:path owner:self];
	
	updateItem = [item retain];
	[self setShouldCascadeWindows:NO];
	
	return self;
}

- (IBAction)relaunchNow:sender
{
	[self close];
	[NSApp stopModalWithCode:NSAlertDefaultReturn];
}

- (IBAction)relaunchLater:sender
{
	[self close];
	[NSApp stopModalWithCode:NSAlertAlternateReturn];
}

- (NSImage *)applicationIcon
{
	return [NSImage imageNamed:@"NSApplicationIcon"];
}

- (NSString *)titleText
{
	return [NSString stringWithFormat:SULocalizedString(@"A new version of %@ has been installed!", nil), SUHostAppDisplayName()];
}

- (NSString *)descriptionText
{
	return [NSString stringWithFormat:SULocalizedString(@"%@ %@ has been installed and will be ready to use next time %@ starts! Would you like to relaunch now?", nil), SUHostAppDisplayName(), [updateItem versionString], SUHostAppDisplayName()];
}

@end
