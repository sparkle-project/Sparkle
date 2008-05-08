//
//  SUUserInitiatedUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/5/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUserInitiatedUpdateDriver.h"
#import "Sparkle.h"

@implementation SUUserInitiatedUpdateDriver

- (void)checkForUpdatesAtURL:(NSURL *)appcastURL hostBundle:(NSBundle *)hb
{
	if ([hostBundle isRunningFromDiskImage])
	{
		[self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SURunningFromDiskImageError userInfo:[NSDictionary dictionaryWithObject:[NSString stringWithFormat:SULocalizedString(@"%1$@ can't be updated when it's running from a disk image. Move %1$@ to your Applications folder, relaunch it, and try again.", nil), [hostBundle name]] forKey:NSLocalizedDescriptionKey]]];
		return;
	}
	[super checkForUpdatesAtURL:appcastURL hostBundle:hb];
}


- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui
{
	// We don't check to see if this update's been skipped, because the user explicitly *asked* if he had the latest version.
	return [self hostSupportsItem:ui] && [self isItemNewer:ui];
}

- (void)didFindValidUpdate
{
	updateAlert = [[SUUpdateAlert alloc] initWithAppcastItem:updateItem hostBundle:hostBundle];
	[updateAlert setDelegate:self];
	
	// Only show the update alert if the app is active; otherwise, we'll wait until it is.
	if ([NSApp isActive])
		[updateAlert showWindow:self];
	else
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
}

- (void)didNotFindUpdate
{
	NSAlert *alert = [NSAlert alertWithMessageText:SULocalizedString(@"You're up to date!", nil) defaultButton:SULocalizedString(@"OK", nil) alternateButton:nil otherButton:nil informativeTextWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.", nil), [hostBundle name], [hostBundle displayVersion]];
	[alert setIcon:[hostBundle icon]];
	[alert runModal];	
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
	[updateAlert showWindow:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"NSApplicationDidBecomeActiveNotification" object:NSApp];
}

- (void)updateAlert:(SUUpdateAlert *)alert finishedWithChoice:(SUUpdateAlertChoice)choice
{
	[updateAlert release]; updateAlert = nil;
	[[SUUserDefaults standardUserDefaults] setObject:nil forKey:SUSkippedVersionKey];
	switch (choice)
	{
		case SUInstallUpdateChoice:
			statusController = [[SUStatusController alloc] initWithHostBundle:hostBundle];
			[statusController beginActionWithTitle:SULocalizedString(@"Downloading update...", nil) maxProgressValue:0 statusText:nil];
			[statusController setButtonTitle:SULocalizedString(@"Cancel", nil) target:self action:@selector(cancelDownload:) isDefault:NO];
			[statusController showWindow:self];			
			[self downloadUpdate];
			break;
			
		case SUSkipThisVersionChoice:
			[[SUUserDefaults standardUserDefaults] setObject:[updateItem versionString] forKey:SUSkippedVersionKey];
		case SURemindMeLaterChoice:
			[self abortUpdate];
			break;			
	}			
}

- (void)download:(NSURLDownload *)download didReceiveResponse:(NSURLResponse *)response
{
	[statusController setMaxProgressValue:[response expectedContentLength]];
}

- (void)download:(NSURLDownload *)download didReceiveDataOfLength:(unsigned)length
{
	[statusController setProgressValue:[statusController progressValue] + length];
	[statusController setStatusText:[NSString stringWithFormat:SULocalizedString(@"%.0lfkb of %.0lfkb", nil), [statusController progressValue] / 1024.0, [statusController maxProgressValue] / 1024.0]];
}

- (IBAction)cancelDownload:sender
{
	if (download)
	{
		[download cancel];
		[download release];
	}
	[self abortUpdate];
}

- (void)extractUpdate
{
	// Now we have to extract the downloaded archive.
	[statusController beginActionWithTitle:SULocalizedString(@"Extracting update...", nil) maxProgressValue:0 statusText:nil];
	[statusController setButtonEnabled:NO];
	[super extractUpdate];
}

- (void)unarchiver:(SUUnarchiver *)ua extractedLength:(long)length
{
	// We do this here instead of in extractUpdate so that we only have a determinate progress bar for archives with progress.
	if ([statusController maxProgressValue] == 0)
		[statusController setMaxProgressValue:[[[[NSFileManager defaultManager] fileAttributesAtPath:downloadPath traverseLink:NO] objectForKey:NSFileSize] longValue]];
	[statusController setProgressValue:[statusController progressValue] + length];
}

- (void)unarchiverDidFinish:(SUUnarchiver *)ua
{
	[statusController beginActionWithTitle:SULocalizedString(@"Ready to Install", nil) maxProgressValue:1 statusText:nil];
	[statusController setProgressValue:1]; // Fill the bar.
	[statusController setButtonEnabled:YES];
	[statusController setButtonTitle:SULocalizedString(@"Install and Relaunch", nil) target:self action:@selector(installAndRestart:) isDefault:YES];
	[NSApp requestUserAttention:NSInformationalRequest];	
}

- (void)installAndRestart:sender { [self installUpdate]; }

- (void)installUpdate
{
	[statusController beginActionWithTitle:SULocalizedString(@"Installing update...", nil) maxProgressValue:0 statusText:nil];
	[statusController setButtonEnabled:NO];
	[super installUpdate];	
}

- (void)abortUpdateWithError:(NSError *)error
{
	NSAlert *alert = [NSAlert alertWithMessageText:SULocalizedString(@"Update Error!", nil) defaultButton:SULocalizedString(@"Cancel Update", nil) alternateButton:nil otherButton:nil informativeTextWithFormat:[error localizedDescription]];
	[alert setIcon:[hostBundle icon]];
	[alert runModal];
	[super abortUpdateWithError:error];
}

- (void)abortUpdate
{
	if (statusController)
	{
		[statusController close];
		[statusController autorelease];
	}
	[super abortUpdate];
}

@end
