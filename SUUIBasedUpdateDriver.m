//
//  SUUIBasedUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/5/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUIBasedUpdateDriver.h"

#import "SUUpdateAlert.h"
#import "SUHost.h"
#import "SUStatusController.h"

@implementation SUUIBasedUpdateDriver

- (IBAction)cancelDownload:sender
{
	if (download)
		[download cancel];
	[self abortUpdate];
}

- (void)didFindValidUpdate
{
	updateAlert = [[SUUpdateAlert alloc] initWithAppcastItem:updateItem host:host];
	[updateAlert setDelegate:self];
	
	if ([[updater delegate] respondsToSelector:@selector(updater:didFindValidUpdate:)])
		[[updater delegate] updater:updater didFindValidUpdate:updateItem];

	// If the app is a menubar app or the like, we need to focus it first and alter the
	// update prompt to behave like a normal window. Otherwise if the window were hidden
	// there may be no way for the application to be activated to make it visible again.
	if ([host isBackgroundApplication])
	{
		[[updateAlert window] setHidesOnDeactivate:NO];
		[NSApp activateIgnoringOtherApps:YES];
	}
	
	// Only show the update alert if the app is active; otherwise, we'll wait until it is.
	if ([NSApp isActive])
		[[updateAlert window] makeKeyAndOrderFront:self];
	else
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:NSApp];
}

- (void)didNotFindUpdate
{
	if ([[updater delegate] respondsToSelector:@selector(updaterDidNotFindUpdate:)])
		[[updater delegate] updaterDidNotFindUpdate:updater];
	NSAlert *alert = [NSAlert alertWithMessageText:SULocalizedString(@"You're up-to-date!", nil) defaultButton:SULocalizedString(@"OK", nil) alternateButton:nil otherButton:nil informativeTextWithFormat:SULocalizedString(@"%@ %@ is currently the newest version available.", nil), [host name], [host displayVersion]];
	[self showModalAlert:alert];
	[self abortUpdate];
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
	[[updateAlert window] makeKeyAndOrderFront:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"NSApplicationDidBecomeActiveNotification" object:NSApp];
}

- (void)updateAlert:(SUUpdateAlert *)alert finishedWithChoice:(SUUpdateAlertChoice)choice
{
	[updateAlert release]; updateAlert = nil;
	[host setObject:nil forUserDefaultsKey:SUSkippedVersionKey];
	switch (choice)
	{
		case SUInstallUpdateChoice:
			statusController = [[SUStatusController alloc] initWithHost:host];
			[statusController beginActionWithTitle:SULocalizedString(@"Downloading update...", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
			[statusController setButtonTitle:SULocalizedString(@"Cancel", nil) target:self action:@selector(cancelDownload:) isDefault:NO];
			[statusController showWindow:self];	
			[self downloadUpdate];
			break;
			
		case SUSkipThisVersionChoice:
			[host setObject:[updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
		case SURemindMeLaterChoice:
			[self abortUpdate];
			break;			
	}			
}

- (void)download:(NSURLDownload *)download didReceiveResponse:(NSURLResponse *)response
{
	[statusController setMaxProgressValue:[response expectedContentLength]];
}

- (NSString *)humanReadableSizeFromDouble:(double)value
{
	if (value < 1000)
		return [NSString stringWithFormat:@"%.0lf %@", value, SULocalizedString(@"B", @"the unit for bytes")];
	
	if (value < 1000 * 1000)
		return [NSString stringWithFormat:@"%.0lf %@", value / 1000.0, SULocalizedString(@"KB", @"the unit for kilobytes")];
	
	if (value < 1000 * 1000 * 1000)
		return [NSString stringWithFormat:@"%.1lf %@", value / 1000.0 / 1000.0, SULocalizedString(@"MB", @"the unit for megabytes")];
	
	return [NSString stringWithFormat:@"%.2lf %@", value / 1000.0 / 1000.0 / 1000.0, SULocalizedString(@"GB", @"the unit for gigabytes")];	
}

- (void)download:(NSURLDownload *)download didReceiveDataOfLength:(NSUInteger)length
{
	[statusController setProgressValue:[statusController progressValue] + (double)length];
	if ([statusController maxProgressValue] > 0.0)
		[statusController setStatusText:[NSString stringWithFormat:SULocalizedString(@"%@ of %@", nil), [self humanReadableSizeFromDouble:[statusController progressValue]], [self humanReadableSizeFromDouble:[statusController maxProgressValue]]]];
	else
		[statusController setStatusText:[NSString stringWithFormat:SULocalizedString(@"%@ downloaded", nil), [self humanReadableSizeFromDouble:[statusController progressValue]]]];
}

- (void)extractUpdate
{
	// Now we have to extract the downloaded archive.
	[statusController beginActionWithTitle:SULocalizedString(@"Extracting update...", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
	[statusController setButtonEnabled:NO];
	[super extractUpdate];
}

- (void)unarchiver:(SUUnarchiver *)ua extractedLength:(unsigned long)length
{
	// We do this here instead of in extractUpdate so that we only have a determinate progress bar for archives with progress.
	if ([statusController maxProgressValue] == 0.0)
	{
		NSDictionary * attributes;
#if MAC_OS_X_VERSION_MIN_REQUIRED <= MAC_OS_X_VERSION_10_4
		attributes = [[NSFileManager defaultManager] fileAttributesAtPath:downloadPath traverseLink:NO];
#else
		attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:downloadPath error:nil];
#endif
		[statusController setMaxProgressValue:[[attributes objectForKey:NSFileSize] doubleValue]];
	}
	[statusController setProgressValue:[statusController progressValue] + (double)length];
}

- (void)installAndRestart:sender { [self installUpdate]; }

- (void)unarchiverDidFinish:(SUUnarchiver *)ua
{
	[statusController beginActionWithTitle:SULocalizedString(@"Ready to Install", nil) maxProgressValue:1.0 statusText:nil];
	[statusController setProgressValue:1.0]; // Fill the bar.
	[statusController setButtonEnabled:YES];
	[statusController setButtonTitle:SULocalizedString(@"Install and Relaunch", nil) target:self action:@selector(installAndRestart:) isDefault:YES];
	[NSApp requestUserAttention:NSInformationalRequest];	
}

- (void)installUpdate
{
	[statusController beginActionWithTitle:SULocalizedString(@"Installing update...", @"Take care not to overflow the status window.") maxProgressValue:0.0 statusText:nil];
	[statusController setButtonEnabled:NO];
	[super installUpdate];
	
	
	// if a user chooses to NOT relaunch the app (as is the case with WebKit
	// when it asks you if you are sure you want to close the app with multiple
	// tabs open), the status window still stays on the screen and obscures
	// other windows; with this fix, it doesn't
	
	if (statusController)
	{
		[statusController close];
		[statusController autorelease];
		statusController = nil;
	}
}

- (void)abortUpdateWithError:(NSError *)error
{
	NSAlert *alert = [NSAlert alertWithMessageText:SULocalizedString(@"Update Error!", nil) defaultButton:SULocalizedString(@"Cancel Update", nil) alternateButton:nil otherButton:nil informativeTextWithFormat:[error localizedDescription]];
	[self showModalAlert:alert];
	[super abortUpdateWithError:error];
}

- (void)abortUpdate
{
	if (statusController)
	{
		[statusController close];
		[statusController autorelease];
		statusController = nil;
	}
	[super abortUpdate];
}

- (void)showModalAlert:(NSAlert *)alert
{
	// When showing a modal alert we need to ensure that background applications
	// are focused to inform the user since there is no dock icon to notify them.
	if ([host isBackgroundApplication]) { [NSApp activateIgnoringOtherApps:YES]; }
	
	[alert setIcon:[host icon]];
	[alert runModal];
}

@end
