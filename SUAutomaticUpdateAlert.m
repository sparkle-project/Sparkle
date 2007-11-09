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

- initWithAppcastItem:(SUAppcastItem *)item andUtilities:(SUUtilities *)aUtility;
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
	utilities = [aUtility retain];
	[self setShouldCascadeWindows:NO];
	
	return self;
}

- (void) dealloc
{
	[utilities release];
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
	return [utilities hostAppIcon];
}

- (NSString *)titleText
{
	return [NSString stringWithFormat:SULocalizedString(@"A new version of %@ has been installed!", nil), [utilities hostAppDisplayName]];
}

- (NSString *)descriptionText
{
	return [NSString stringWithFormat:SULocalizedString(@"%@ %@ has been installed and will be ready to use next time %@ starts! Would you like to relaunch now?", nil), [utilities hostAppDisplayName], [updateItem versionString], [utilities hostAppDisplayName]];
}

@end
