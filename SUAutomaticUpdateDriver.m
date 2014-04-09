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
	isInterruptible = NO;
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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];

    // Sudden termination is available on 10.6+
    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    [processInfo disableSuddenTermination];

    willUpdateOnTermination = YES;

    if ([[updater delegate] respondsToSelector:@selector(updater:willInstallUpdateOnQuit:immediateInstallationInvocation:)])
    {
        BOOL relaunch = YES;
        BOOL showUI = NO;
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:@selector(installWithToolAndRelaunch:displayingUserInterface:)]];
        [invocation setSelector:@selector(installWithToolAndRelaunch:displayingUserInterface:)];
        [invocation setArgument:&relaunch atIndex:2];
        [invocation setArgument:&showUI atIndex:3];
        [invocation setTarget:self];

        [[updater delegate] updater:updater willInstallUpdateOnQuit:updateItem immediateInstallationInvocation:invocation];
    }

    // If this is marked as a critical update, we'll prompt the user to install it right away. 
    if ([updateItem isCriticalUpdate])
    {
        [self showUpdateAlert];
    }
    else
    {
        showUpdateAlertTimer = [[NSTimer scheduledTimerWithTimeInterval:SUAutomaticUpdatePromptImpatienceTimer target:self selector:@selector(showUpdateAlert) userInfo:nil repeats:NO] retain];

        // At this point the driver is idle, allow it to be interrupted for user-initiated update checks.
        isInterruptible = YES;
    }
}

- (void)stopUpdatingOnTermination
{
    if (willUpdateOnTermination)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationWillTerminateNotification object:nil];
        NSProcessInfo *processInfo = [NSProcessInfo processInfo];
        [processInfo enableSuddenTermination];
        
        willUpdateOnTermination = NO;

        if ([[updater delegate] respondsToSelector:@selector(updater:didCancelInstallUpdateOnQuit:)])
            [[updater delegate] updater:updater didCancelInstallUpdateOnQuit:updateItem];
    }
}

- (void)invalidateShowUpdateAlertTimer
{
    [showUpdateAlertTimer invalidate];
    [showUpdateAlertTimer release];
    showUpdateAlertTimer = nil;    
}

- (void)dealloc
{
    [self stopUpdatingOnTermination];
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
			postponingInstallation = YES;
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
			// We're already waiting on quit, just indicate that we're idle.
			isInterruptible = YES;
			break;

		case SUDoNotInstallChoice:
			[host setObject:[updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
			[self abortUpdate];
			break;
	}
}

- (BOOL)shouldInstallSynchronously { return postponingInstallation; }

- (void)installWithToolAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI
{
    if (relaunch)
        [self stopUpdatingOnTermination];

    showErrors = YES;
    [super installWithToolAndRelaunch:relaunch displayingUserInterface:showUI];
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
