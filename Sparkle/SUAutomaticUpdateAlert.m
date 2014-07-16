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
@property (strong) SUAppcastItem *updateItem;
@property (weak) id<SUAutomaticUpdateAlertDelegate> delegate;
@property (strong) SUHost *host;
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

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@, %@>", [self class], [self.host bundlePath], [self.host installationPath]]; }

- (IBAction)installNow:(id)__unused sender
{
    [self close];
    [self.delegate automaticUpdateAlert:self finishedWithChoice:SUInstallNowChoice];
}

- (IBAction)installLater:(id)__unused sender
{
    [self close];
    [self.delegate automaticUpdateAlert:self finishedWithChoice:SUInstallLaterChoice];
}

- (IBAction)doNotInstall:(id)__unused sender
{
    [self close];
    [self.delegate automaticUpdateAlert:self finishedWithChoice:SUDoNotInstallChoice];
}

- (NSImage *)applicationIcon
{
    return [self.host icon];
}

- (NSString *)titleText
{
    if ([self.updateItem isCriticalUpdate])
    {
        return [NSString stringWithFormat:SULocalizedString(@"An important update to %@ is ready to install", nil), [self.host name]];
    }
    else
    {
        return [NSString stringWithFormat:SULocalizedString(@"A new version of %@ is ready to install!", nil), [self.host name]];
    }
}

- (NSString *)descriptionText
{
    if ([self.updateItem isCriticalUpdate])
    {
        return [NSString stringWithFormat:SULocalizedString(@"%1$@ %2$@ has been downloaded and is ready to use! This is an important update; would you like to install it and relaunch %1$@ now?", nil), [self.host name], [self.updateItem displayVersionString]];
    }
    else
    {
        return [NSString stringWithFormat:SULocalizedString(@"%1$@ %2$@ has been downloaded and is ready to use! Would you like to install it and relaunch %1$@ now?", nil), [self.host name], [self.updateItem displayVersionString]];
    }
}

@end
