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
#import "SUUpdater_Private.h"
#import "SUXPCURLDownload.h"

@implementation SUAutomaticUpdateDriver

// -------------------------------------------------------------------
#if SPARKLE_IS_COMPATIBLE_WITH_DEVMATE

static NSString * const kSUAutomaticUpdateParamName = @"autoupdate";

- (void)downloadReleaseNotesAndWaitUntilDone
{
    NSURL *releaseNotesURL = [updateItem releaseNotesURL];
    if (nil == releaseNotesURL || [releaseNotesURL isFileURL])
        return;
    
    NSString *URLString = [releaseNotesURL absoluteString];
    URLString = [URLString stringByAppendingFormat:@"%@%@=1", ([releaseNotesURL query] != nil) ? @"&" : @"?", kSUAutomaticUpdateParamName];
    releaseNotesURL = [NSURL URLWithString:URLString];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:releaseNotesURL];
    [request setCachePolicy:NSURLRequestReloadIgnoringCacheData];
    [self updateURLRequestIfNeeds:request];
    
    if (SUShouldUseXPCDownloader())
    {
        [SUXPCURLDownload sendSynchronousRequest:request delegate:nil];
    }
    else
    {
        [NSURLConnection sendSynchronousRequest:request returningResponse:NULL error:NULL];
    }
}

- (void)didFindValidUpdate
{
    // For correct DevMate statistics need to send request for Release Notes.
    [self downloadReleaseNotesAndWaitUntilDone];
    [super didFindValidUpdate];
}

#endif // SPARKLE_IS_COMPATIBLE_WITH_DEVMATE
// -------------------------------------------------------------------

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
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationDidBecomeActiveNotification object:NSApp];
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
