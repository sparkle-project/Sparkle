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

// If the user hasn't quit in a week, ask them if they want to relaunch to get the latest bits. It doesn't matter that this measure of "one day" is imprecise.
static const NSTimeInterval SUAutomaticUpdatePromptImpatienceTimer = 60 * 60 * 24 * 7;

@implementation SUAutomaticUpdateDriver

- (void)showUpdateAlert
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

- (void)unarchiverDidFinish:(SUUnarchiver *)ua
{
    // If this is marked as a critical update, we'll prompt the user to install it right away. 
    if ([updateItem isCriticalUpdate])
    {
        [self showUpdateAlert];
    }
    else if ([[updater delegate] respondsToSelector:@selector(updaterShouldPromptInstall:)]) {
        BOOL prompt = [[updater delegate] updaterShouldPromptInstall:updater];
        if (prompt) {
            [self showUpdateAlert];
        }
        else {
            [self installWithToolAndRelaunch:NO];
        }
    }
    else
    {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
        showUpdateAlertTimer = [[NSTimer scheduledTimerWithTimeInterval:SUAutomaticUpdatePromptImpatienceTimer target:self selector:@selector(showUpdateAlert) userInfo:nil repeats:NO] retain];
    }
}

- (void)stopUpdatingOnTermination
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationWillTerminateNotification object:nil];
}

- (void)invalidateShowUpdateAlertTimer
{
    [showUpdateAlertTimer invalidate];
    [showUpdateAlertTimer release];
    showUpdateAlertTimer = nil;    
}

- (void)dealloc
{
    [self invalidateShowUpdateAlertTimer];
    [alert release];
    [super dealloc];
}

- (void)abortUpdate
{
    [self stopUpdatingOnTermination];
    [self invalidateShowUpdateAlertTimer];
    [super abortUpdate];
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
            [self stopUpdatingOnTermination];
			[self installWithToolAndRelaunch:YES];
			break;
			
		case SUInstallLaterChoice:
            // No-op: we're already waiting on quit.
			break;

		case SUDoNotInstallChoice:
			[host setObject:[updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
			[self abortUpdate];
			break;
	}
}

- (void)installWithToolAndRelaunch:(BOOL)relaunch
{
	showErrors = YES;
    if ([[updater delegate] respondsToSelector: @selector(updaterShouldRelaunchApplication:)])
        relaunch = [[updater delegate] updaterShouldRelaunchApplication: updater];
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
