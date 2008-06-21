//
//  SUUserInitiatedUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/30/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUserInitiatedUpdateDriver.h"
#import "Sparkle.h"

@implementation SUUserInitiatedUpdateDriver

- (void)checkForUpdatesAtURL:(NSURL *)appcastURL hostBundle:(NSBundle *)hb
{
	[super checkForUpdatesAtURL:appcastURL hostBundle:hb];
	checkingController = [[SUStatusController alloc] initWithHostBundle:hb];
	[checkingController window]; // Force the checking controller to load its window.
	[checkingController beginActionWithTitle:SULocalizedString(@"Checking for updates\u2026", nil) maxProgressValue:0 statusText:nil];
	[checkingController setButtonHidden:YES];
	[checkingController showWindow:self];
}

- (void)closeCheckingWindow
{
	[[checkingController window] close];
	[checkingController release];
}

- (void)appcast:(SUAppcast *)ac failedToLoadWithError:(NSError *)error
{
	[self closeCheckingWindow];
	[super appcast:ac failedToLoadWithError:error];
}

- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui
{
	// We don't check to see if this update's been skipped, because the user explicitly *asked* if he had the latest version.
	return [self hostSupportsItem:ui] && [self isItemNewer:ui];
}

- (void)didNotFindUpdate
{
	[self closeCheckingWindow];
	[super didNotFindUpdate];
}

- (void)didFindValidUpdate
{
	[self closeCheckingWindow];
	[super didFindValidUpdate];
}

@end
