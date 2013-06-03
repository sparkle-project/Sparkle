//
//  SUAutomaticUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/6/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUAutomaticUpdateDriver.h"

#import "SUAutomaticUpdateAlert.h"
#import "SUHost.h"
#import "SUConstants.h"

@implementation SUAutomaticUpdateDriver

- (void)unarchiverDidFinish:(SUUnarchiver *)ua
{
	alert = [[SUAutomaticUpdateAlert alloc] initWithAppcastItem:updateItem host:host delegate:self];
	
	// If the app is a menubar app or the like, we need to focus it first and alter the
	// update prompt to behave like a normal window. Otherwise if the window were hidden
	// there may be no way for the application to be activated to make it visible again.
	if ([host isBackgroundApplication])
	{
		[[alert window] setHidesOnDeactivate:NO];
		[NSApp activateIgnoringOtherApps:YES];
	}		
	
	if ([NSApp isActive])
		[[alert window] makeKeyAndOrderFront:self];
	else
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive:) name:NSApplicationDidBecomeActiveNotification object:NSApp];	
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification
{
	[[alert window] makeKeyAndOrderFront:self];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:@"NSApplicationDidBecomeActiveNotification" object:NSApp];
}

- (void)automaticUpdateAlert:(SUAutomaticUpdateAlert *)aua finishedWithChoice:(SUAutomaticInstallationChoice)choice;
{
	switch (choice)
	{
		case SUInstallNowChoice:
			[self installWithToolAndRelaunch:YES];
			break;
			
		case SUInstallLaterChoice:
			postponingInstallation = YES;
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
			break;

		case SUDoNotInstallChoice:
			[host setObject:[updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
			[self abortUpdate];
			break;
	}
}


- (void)download:(NSURLDownload *)download didReceiveResponse:(NSURLResponse *)response
{
	if ([[updater delegate] respondsToSelector:@selector(setMaxProgressValue:)])
		[[updater delegate] setMaxProgressValue:[response expectedContentLength]];
}

- (void)download:(NSURLDownload *)download didReceiveDataOfLength:(NSUInteger)length
{
    if ([[updater delegate] respondsToSelector:@selector(progressValue)] && [[updater delegate] respondsToSelector:@selector(setProgressValue:)]) {
        [[updater delegate] setProgressValue:[[updater delegate] progressValue] + (double)length];
    }
    if ([[updater delegate] respondsToSelector:@selector(maxProgressValue)] && [[updater delegate] respondsToSelector:@selector(setStatusText:)]) {
        if ([[updater delegate] maxProgressValue] > 0.0) {
            [[updater delegate] setStatusText:[NSString stringWithFormat:SULocalizedString(@"%@ of %@", nil), [self humanReadableSizeFromDouble:[[updater delegate] progressValue]], [self humanReadableSizeFromDouble:[[updater delegate] maxProgressValue]]]];
        } else {
            [[updater delegate] setStatusText:[NSString stringWithFormat:SULocalizedString(@"%@ downloaded", nil), [self humanReadableSizeFromDouble:[[updater delegate] progressValue]]]];
        }
    }
}

- (BOOL)shouldInstallSynchronously { return postponingInstallation; }

- (void)installWithToolAndRelaunch:(BOOL)relaunch
{
	showErrors = YES;
	[super installWithToolAndRelaunch:relaunch];
}

- (void)applicationWillTerminate:(NSNotification *)note
{
	[self installWithToolAndRelaunch:NO];
}

- (void)abortUpdateWithError:(NSError *)error
{
	if (showErrors)
		[super abortUpdateWithError:error];
	else
		[self abortUpdate];
}

@end
