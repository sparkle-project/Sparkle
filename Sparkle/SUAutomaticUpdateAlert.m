//
//  SUAutomaticUpdateAlert.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/18/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUAutomaticUpdateAlert.h"

#import "SUHost.h"

@interface SUAutomaticUpdateAlert ()
@property (retain) SUAppcastItem *updateItem;
@property (assign) id<SUAutomaticUpdateAlertDelegate> delegate;
@property (retain) SUHost *host;
@end

@implementation SUAutomaticUpdateAlert
@synthesize delegate;
@synthesize host;
@synthesize updateItem;

- (instancetype)initWithAppcastItem:(SUAppcastItem *)item host:(SUHost *)aHost delegate:(id<SUAutomaticUpdateAlertDelegate>)del
{
	self = [super initWithHost:aHost windowNibName:@"SUAutomaticUpdateAlert"];
	if (self)
	{
		self.updateItem = item;
		self.delegate = del;
		self.host = aHost;
		[self setShouldCascadeWindows:NO];
		[[self window] center];
	}
	return self;
}

- (void)dealloc
{
	self.host = nil;
	self.updateItem = nil;
	[super dealloc];
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@, %@>", [self class], [host bundlePath], [host installationPath]]; }

- (IBAction)installNow:(id) __unused sender
{
	[self close];
	[delegate automaticUpdateAlert:self finishedWithChoice:SUInstallNowChoice];
}

- (IBAction)installLater:(id) __unused sender
{
	[self close];
	[delegate automaticUpdateAlert:self finishedWithChoice:SUInstallLaterChoice];
}

- (IBAction)doNotInstall:(id) __unused sender
{
	[self close];
	[delegate automaticUpdateAlert:self finishedWithChoice:SUDoNotInstallChoice];
}

- (NSImage *)applicationIcon
{
	return [host icon];
}

- (NSString *)titleText
{
    if ([updateItem isCriticalUpdate])
    {
        return [NSString stringWithFormat:SULocalizedString(@"An important update to %@ is ready to install", nil), [host name]];
    }
    else
    {
        return [NSString stringWithFormat:SULocalizedString(@"A new version of %@ is ready to install!", nil), [host name]];
    }
}

- (NSString *)descriptionText
{
    if ([updateItem isCriticalUpdate])
    {
        return [NSString stringWithFormat:SULocalizedString(@"%1$@ %2$@ has been downloaded and is ready to use! This is an important update; would you like to install it and relaunch %1$@ now?", nil), [host name], [updateItem displayVersionString]];
    }
    else
    {
        return [NSString stringWithFormat:SULocalizedString(@"%1$@ %2$@ has been downloaded and is ready to use! Would you like to install it and relaunch %1$@ now?", nil), [host name], [updateItem displayVersionString]];
    }
}

@end
