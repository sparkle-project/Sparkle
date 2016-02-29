//
//  SUAutomaticUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/6/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUAutomaticUpdateDriver.h"
#import "SULocalizations.h"
#import "SUUpdater.h"
#import "SUHost.h"
#import "SUConstants.h"
#import "SUErrors.h"
#import "SUAppcastItem.h"
#import "SULog.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

// If the user hasn't quit in a week, ask them if they want to relaunch to get the latest bits. It doesn't matter that this measure of "one day" is imprecise.
static const NSTimeInterval SUAutomaticUpdatePromptImpatienceTimer = 60 * 60 * 24 * 7;

@interface SUUpdateDriver ()

@property (getter=isInterruptible) BOOL interruptible;

@end

@interface SUAutomaticUpdateDriver ()

@property (assign) BOOL postponingInstallation;
@property (assign) BOOL showErrors;
@property (assign) BOOL willUpdateOnTermination;
@property (strong) NSTimer *showUpdateAlertTimer;

@end

@implementation SUAutomaticUpdateDriver

@synthesize postponingInstallation;
@synthesize showErrors;
@synthesize willUpdateOnTermination;
@synthesize showUpdateAlertTimer;

- (void)showUpdateAlert
{
    self.interruptible = NO;
    
    [self.updater.userUpdaterDriver showAutomaticUpdateFoundWithAppcastItem:self.updateItem reply:^(SUAutomaticInstallationChoice choice) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self automaticUpdateAlertFinishedWithChoice:choice];
        });
    }];
}

- (void)installUpdateWithTerminationStatus:(NSNumber *)terminationStatus
{
    switch ((SUApplicationTerminationStatus)(terminationStatus.unsignedIntegerValue)) {
        case SUApplicationStoppedObservingTermination:
            if (self.willUpdateOnTermination) {
                [self abortUpdate];
            }
            break;
        case SUApplicationWillTerminate:
            if (self.willUpdateOnTermination) {
                [self installWithToolAndRelaunch:NO];
            }
            break;
    }
}

- (void)unarchiverDidFinish:(SUUnarchiver *)__unused ua
{
    [self.updater.userUpdaterDriver registerApplicationTermination:^(SUApplicationTerminationStatus terminationStatus) {
        // We use -performSelectorOnMainThread:withObject:waitUntilDone: rather than GCD because if we are on the main thread already,
        // we don't want to run the operation asynchronously. It's also possible we aren't on the main thread (say due to IPC through a XPC service).
        // Anyway, if we're on the main thread in a single process without the app delegate delaying termination,
        // we could be terminating *really soon* - so we want to install the update quickly
        [self performSelectorOnMainThread:@selector(installUpdateWithTerminationStatus:) withObject:@(terminationStatus) waitUntilDone:YES];
    }];
    
    [self.updater.userUpdaterDriver registerSystemPowerOff:^(SUSystemPowerOffStatus systemPowerOffStatus) {
        // See above comment for why we use -performSelectorOnMainThread:withObject:waitUntilDone:
        [self performSelectorOnMainThread:@selector(systemWillPowerOff:) withObject:@(systemPowerOffStatus) waitUntilDone:YES];
    }];

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
        self.willUpdateOnTermination = NO;
        
        [self.updater.userUpdaterDriver unregisterApplicationTermination];
        [self.updater.userUpdaterDriver unregisterSystemPowerOff];

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
    [self stopUpdatingOnTermination];
    [self invalidateShowUpdateAlertTimer];
    
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

- (void)systemWillPowerOff:(NSNumber *)systemPowerOffStatus
{
    if (self.willUpdateOnTermination) {
        switch ((SUSystemPowerOffStatus)(systemPowerOffStatus.unsignedIntegerValue)) {
            case SUStoppedObservingSystemPowerOff:
                [self abortUpdate];
                break;
            case SUSystemWillPowerOff:
                [self abortUpdateWithError:[NSError errorWithDomain:SUSparkleErrorDomain code:SUSystemPowerOffError userInfo:@{
                    NSLocalizedDescriptionKey: SULocalizedString(@"The update will not be installed because the user requested for the system to power off", nil) }]];
                break;
        }
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
