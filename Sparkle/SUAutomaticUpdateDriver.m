//
//  SUAutomaticUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/6/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUAutomaticUpdateDriver.h"
#import "SULocalizations.h"
#import "SUUpdaterDelegate.h"
#import "SUHost.h"
#import "SUConstants.h"
#import "SUErrors.h"
#import "SUAppcastItem.h"
#import "SULog.h"
#import "SUStatusCompletionResults.h"
#import "SUUserDriver.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

// If the user hasn't quit in a week, ask them if they want to relaunch to get the latest bits. It doesn't matter that this measure of "one day" is imprecise.
static const NSTimeInterval SUAutomaticUpdatePromptImpatienceTimer = 60 * 60 * 24 * 7;

@interface SUUpdateDriver ()

@property (getter=isInterruptible) BOOL interruptible;

@end

@interface SUAutomaticUpdateDriver ()

@property (strong) NSTimer *showUpdateAlertTimer;

@end

@implementation SUAutomaticUpdateDriver

@synthesize showUpdateAlertTimer = _showUpdateAlertTimer;

- (void)showUpdateAlert
{
    self.interruptible = NO;
    
    [self.userDriver showAutomaticUpdateFoundWithAppcastItem:self.updateItem reply:^(SUUpdateAlertChoice choice) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self automaticUpdateAlertFinishedWithChoice:choice];
        });
    }];
}

- (void)automaticUpdateAlertFinishedWithChoice:(SUUpdateAlertChoice)choice
{
    switch (choice)
    {
        case SUInstallUpdateChoice:
            [self installWithToolAndRelaunch:YES displayingUserInterface:YES];
            break;
            
        case SUInstallLaterChoice:
            [self installWithToolAndRelaunch:NO displayingUserInterface:NO];
            // We're already waiting on quit, just indicate that we're idle.
            self.interruptible = YES;
            break;
            
        case SUSkipThisVersionChoice:
#warning this option should not exist
            [self.host setObject:[self.updateItem versionString] forUserDefaultsKey:SUSkippedVersionKey];
            [self abortUpdate];
            break;
    }
}

- (void)installerIsReadyForRelaunch
{
    if ([self.updaterDelegate respondsToSelector:@selector(updater:willInstallUpdateOnQuit:immediateInstallationInvocation:)])
    {
        BOOL relaunch = YES;
        BOOL showUI = NO;
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[[self class] instanceMethodSignatureForSelector:@selector(installWithToolAndRelaunch:displayingUserInterface:)]];
        [invocation setSelector:@selector(installWithToolAndRelaunch:displayingUserInterface:)];
        [invocation setArgument:&relaunch atIndex:2];
        [invocation setArgument:&showUI atIndex:3];
        [invocation setTarget:self];

        [self.updaterDelegate updater:self.updater willInstallUpdateOnQuit:self.updateItem immediateInstallationInvocation:invocation];
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

- (void)installWithToolAndRelaunch:(BOOL)relaunch displayingUserInterface:(BOOL)showUI
{
    [super installWithToolAndRelaunch:relaunch displayingUserInterface:showUI];
}

- (void)abortUpdate
{
    [self.showUpdateAlertTimer invalidate];
    self.showUpdateAlertTimer = nil;
    
    [super abortUpdate];
}

@end
