//
//  SUAutomaticUpdateAlert.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/18/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "Sparkle.h"
#import "SUAutomaticUpdateAlert.h"

@implementation SUAutomaticUpdateAlert

- (id)initWithAppcastItem:(SUAppcastItem *)item hostBundle:(NSBundle *)hb delegate:del;
{
	self = [super initWithHostBundle:hb windowNibName:@"SUAutomaticUpdateAlert"];
	if (self)
	{
		updateItem = [item retain];
		delegate = del;
		hostBundle = [hb retain];
		[self setShouldCascadeWindows:NO];	
		[[self window] center];
	}
	return self;
}

- (void)dealloc
{
	[hostBundle release];
	[updateItem release];
	[super dealloc];
}


- (IBAction)installNow:sender
{
	[self close];
	[delegate automaticUpdateAlert:self finishedWithChoice:SUInstallNowChoice];
}

- (IBAction)installLater:sender
{
	[self close];
	[delegate automaticUpdateAlert:self finishedWithChoice:SUInstallLaterChoice];
}

- (IBAction)doNotInstall:sender
{
	[self close];
	[delegate automaticUpdateAlert:self finishedWithChoice:SUDoNotInstallChoice];
}

- (NSImage *)applicationIcon
{
	return [hostBundle icon];
}

- (NSString *)titleText
{
	return [NSString stringWithFormat:SULocalizedString(@"A new version of %@ is ready to install!", nil), [hostBundle name]];
}

- (NSString *)descriptionText
{
	return [NSString stringWithFormat:SULocalizedString(@"%1$@ %2$@ has been downloaded and is ready to use! Would you like to install it and relaunch %1$@ now?", nil), [hostBundle name], [hostBundle displayVersion]];
}

@end
