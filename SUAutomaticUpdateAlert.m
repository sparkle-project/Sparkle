//
//  SUAutomaticUpdateAlert.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/18/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUAutomaticUpdateAlert.h"

@implementation SUAutomaticUpdateAlert

- initWithAppcastItem:(SUAppcastItem *)item hostBundle:(NSBundle *)hb;
{
	updateItem = [item retain];
	hostBundle = [hb retain];

	NSString *path = [[NSBundle bundleForClass:[self class]] pathForResource:@"SUAutomaticUpdateAlert" ofType:@"nib"];
	if (path == nil) // Slight hack to resolve issues with running Sparkle in debug configurations.
	{
		NSString *frameworkPath = [[hostBundle sharedFrameworksPath] stringByAppendingString:@"/Sparkle.framework"];
		NSBundle *framework = [NSBundle bundleWithPath:frameworkPath];
		path = [framework pathForResource:@"SUAutomaticUpdateAlert" ofType:@"nib"];
	}
	
	[super initWithWindowNibPath:path owner:self];
	[self setShouldCascadeWindows:NO];
	
	return self;
}

- (void) dealloc
{
	[hostBundle release];
	[updateItem release];
	[super dealloc];
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
	return [hostBundle icon];
}

- (NSString *)titleText
{
	return [NSString stringWithFormat:SULocalizedString(@"A new version of %@ has been installed!", nil), [hostBundle name]];
}

- (NSString *)descriptionText
{
	return [NSString stringWithFormat:SULocalizedString(@"%1$@ %2$@ has been installed and will be ready to use next time %1$@ starts! Would you like to relaunch now?", nil), [hostBundle name], [hostBundle displayVersion]];
}

@end
