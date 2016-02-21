//
//  SUAutomaticUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/6/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUAutomaticUpdateDriver.h"

#import "SUUpdater.h"
#import "SUHost.h"
#import "SUConstants.h"

// If the user hasn't quit in a week, ask them if they want to relaunch to get the latest bits. It doesn't matter that this measure of "one day" is imprecise.
static const NSTimeInterval SUAutomaticUpdatePromptImpatienceTimer = 60 * 60 * 24 * 7;

@interface SUUpdateDriver ()

@property (getter=isInterruptible) BOOL interruptible;

@end

@interface SUAutomaticUpdateDriver ()

@property (assign) BOOL postponingInstallation;
@property (assign) BOOL showErrors;
@property (assign) BOOL willUpdateOnTermination;
@property (assign) BOOL isTerminating;
@property (strong) NSTimer *showUpdateAlertTimer;

@end

@implementation SUAutomaticUpdateDriver

@synthesize postponingInstallation;
@synthesize showErrors;
@synthesize willUpdateOnTermination;
@synthesize isTerminating;
@synthesize showUpdateAlertTimer;

- (void)showUpdateAlert
{
    self.interruptible = NO;
    
    [self.updater.userUpdaterDriver showAutomaticUpdateFoundWithAppcastItem:self.updateItem reply:^(SUAutomaticInstallationChoice choice) {
        [self automaticUpdateAlertFinishedWithChoice:choice];
    }];
}

- (void)unarchiverDidFinish:(SUUnarchiver *)__unused ua
{
    [self.updater.userUpdaterDriver registerForAppTermination:^{
        // We don't want to terminate the app if the user or someone else initiated a termination
        // Use a property instead of passing an argument to installWithToolAndRelaunch:
        // because we give the delegate an invocation to our install methods and
        // this code was added later :|
        self.isTerminating = YES;
        
        [self installWithToolAndRelaunch:NO];
    }];
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(systemWillPowerOff:) name:NSWorkspaceWillPowerOffNotification object:nil];

    self.willUpdateOnTermination = YES;

    id<SUUpdaterDelegate> updaterDelegate = [self.updater delegate];
    if ([updaterDelegate respondsToSelector:@selector(updater:willInstallUpdateOnQuit:immediateInstallationInvocation:)])
    {
        BOOL relaunch = YES;
        BOOL showUI = NO;
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:@selector(installWithToolAndRelaunch:displayingUserInterface:)]];
        [invocation setSelector:@selector(installWithToolAndRelaunch:displayingUserInterface:)];
        [invocation setArgument:&relaunch atIndex:2];
        [invocation setArgument:&showUI atIndex:3];
        [invocation setTarget:self];

        [updaterDelegate updater:self.updater willInstallUpdateOnQuit:self.updateItem immediateInstallationInvocation:invocation];
    }

    // If this is marked as a critical update, we'll prompt the user to install it right away.
    if ([self.updateItem isCriticalUpdate])
    {
        [self showUpdateAlert];
    }
    else
    {
        self.showUpdateAlertTimer = [NSTimer scheduledTimerWithTimeInterval:SUAutomaticUpdatePromptImpatienceTimer target:self selector:@selector(showUpdateAlert) userInfo:nil repeats:NO];

        // At this point the driver is idle, allow it to be interrupted for user-initiated update checks.
        self.interruptible = YES;
    }
}

- (void)stopUpdatingOnTermination
{
    if (self.willUpdateOnTermination)
    {
        [self.updater.userUpdaterDriver unregisterForAppTermination];
        
        [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self name:NSWorkspaceWillPowerOffNotification object:nil];

        self.willUpdateOnTermination = NO;

        id<SUUpdaterDelegate> updaterDelegate = [self.updater delegate];
        if ([updaterDelegate respondsToSelector:@selector(updater:didCancelInstallUpdateOnQuit:)])
            [updaterDelegate updater:self.updater didCancelInstallUpdateOnQuit:self.updateItem];
    }
}

- (void)invalidateShowUpdateAlertTimer
{
    [self.showUpdateAlertTimer invalidate];
    self.showUpdateAlertTimer = nil;
}

- (void)dealloc
{
    [self stopUpdatingOnTermination];
    [self invalidateShowUpdateAlertTimer];
}

- (void)abortUpdate
{
    self.isTerminating = NO;
    [self stopUpdatingOnTermination];
    [self invalidateShowUpdateAlertTimer];
    
    [self.updater.userUpdaterDriver dismissUpdateInstallation];
    
    [super abortUpdate];
}

- (void)automaticUpdateAlertFinishedWithChoice:(SUAutomaticInstallationChoice)choice
{
	switch (choice)
	{
        case SUInstallNowChoice:
            [self stopUpdatingOnTermination];
            [self installWithToolAndRelaunch:YES];
            break;

        case SUInstallLaterChoice:
            self.postponingInstallation = YES;
            // We're already waiting on quit, just indicate that we're idle.
            self.interruptible = YES;
            break;

        case SUDoNotInstallChoice:
            [self.host setObject:[self.updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
            [self abortUpdate];
            break;
    }
}


- (void)installWithToolAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI
{
    if (relaunch) {
        [self stopUpdatingOnTermination];
    }

    self.showErrors = YES;
    [super installWithToolAndRelaunch:relaunch displayingUserInterface:showUI];
}

- (void)systemWillPowerOff:(NSNotification *)__unused note
{
    [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUSystemPowerOffError userInfo:@{
        NSLocalizedDescriptionKey: SULocalizedString(@"The update will not be installed because the user requested for the system to power off", nil)
    }]];
}

- (void)terminateApp
{
    if (!self.isTerminating) {
        [super terminateApp];
    }
}

- (void)abortUpdateWithError:(NSError *)error
{
    if (self.showErrors) {
        [super abortUpdateWithError:error];
    } else {
        // Call delegate separately here because otherwise it won't know we stopped.
        // Normally this gets called by the superclass
        id<SUUpdaterDelegate> updaterDelegate = [self.updater delegate];
        if ([updaterDelegate respondsToSelector:@selector(updater:didAbortWithError:)]) {
            [updaterDelegate updater:self.updater didAbortWithError:error];
        }

        [self abortUpdate];
    }
}

@end
