//
//  SUUserInitiatedUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/30/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUserInitiatedUpdateDriver.h"

#import "SUStatusController.h"
#import "SUHost.h"

@implementation SUUserInitiatedUpdateDriver

- (void)checkForUpdatesAtURL:(NSURL *)URL host:(SUHost *)aHost
{
	checkingController = [[SUStatusController alloc] initWithHost:aHost];
	[[checkingController window] center]; // Force the checking controller to load its window.
	[checkingController beginActionWithTitle:SULocalizedString(@"Checking for updates...", nil) maxProgressValue:0 statusText:nil];
	[checkingController setButtonTitle:SULocalizedString(@"Cancel", nil) target:self action:@selector(cancelCheckForUpdates:) isDefault:NO];
	[checkingController showWindow:self];
	[super checkForUpdatesAtURL:URL host:aHost];
	
	// For background applications, obtain focus.
	// Useful if the update check is requested from another app like System Preferences.
	if ([aHost isBackgroundApplication])
	{
		[NSApp activateIgnoringOtherApps:YES];
	}
}

- (void)closeCheckingWindow
{
	if (checkingController)
	{
		[[checkingController window] close];
		[checkingController release];
		checkingController = nil;
	}
}

- (void)cancelCheckForUpdates:sender
{
	[self closeCheckingWindow];
	isCanceled = YES;
}

- (void)appcastDidFinishLoading:(SUAppcast *)ac
{
	if (isCanceled)
	{
		[self abortUpdate];
		return;
	}
	[self closeCheckingWindow];
	[super appcastDidFinishLoading:ac];
}

- (void)abortUpdateWithError:(NSError *)error
{
	[self closeCheckingWindow];
	[super abortUpdateWithError:error];
}

- (void)abortUpdate
{
	[self closeCheckingWindow];
	[super abortUpdate];
}

- (void)appcast:(SUAppcast *)ac failedToLoadWithError:(NSError *)error
{
	if (isCanceled)
	{
		[self abortUpdate];
		return;
	}
	[super appcast:ac failedToLoadWithError:error];
}

- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui
{
	// We don't check to see if this update's been skipped, because the user explicitly *asked* if he had the latest version.
	return [self hostSupportsItem:ui] && [self isItemNewer:ui];
}

@end
