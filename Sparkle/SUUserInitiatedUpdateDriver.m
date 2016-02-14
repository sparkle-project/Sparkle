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

@interface SUUserInitiatedUpdateDriver ()

@property (strong) SUStatusController *checkingController;
@property (assign, getter=isCanceled) BOOL canceled;

@end

@implementation SUUserInitiatedUpdateDriver

@synthesize checkingController;
@synthesize canceled;

- (void)closeCheckingWindow
{
    BOOL delegateHandledUpdaterCheck = NO;
    if ([self.updater.delegate respondsToSelector:@selector(stopUserInitiatedUpdateCheckWithUpdater:host:)]) {
        delegateHandledUpdaterCheck = [self.updater.delegate stopUserInitiatedUpdateCheckWithUpdater:self.updater host:self.host];
    }
    
	if (!delegateHandledUpdaterCheck && self.checkingController)
	{
        [[self.checkingController window] close];
        self.checkingController = nil;
    }
}

- (void)cancelCheckForUpdates:(id)__unused sender
{
    [self closeCheckingWindow];
    self.canceled = YES;
}

- (void)checkForUpdatesAtURL:(NSURL *)URL host:(SUHost *)aHost
{
    BOOL delegateHandledUpdaterCheck = NO;
    if ([self.updater.delegate respondsToSelector:@selector(startUserInitiatedUpdateCheckWithUpdater:host:cancelUpdateCheck:)]) {
        delegateHandledUpdaterCheck = [self.updater.delegate startUserInitiatedUpdateCheckWithUpdater:self.updater host:self.host cancelUpdateCheck:^{
            [self cancelCheckForUpdates:nil];
        }];
    }
    
    if (!delegateHandledUpdaterCheck) {
        self.checkingController = [[SUStatusController alloc] initWithHost:aHost];
        [[self.checkingController window] center]; // Force the checking controller to load its window.
        [self.checkingController beginActionWithTitle:SULocalizedString(@"Checking for updates...", nil) maxProgressValue:0.0 statusText:nil];
        [self.checkingController setButtonTitle:SULocalizedString(@"Cancel", nil) target:self action:@selector(cancelCheckForUpdates:) isDefault:NO];
        [self.checkingController showWindow:self];
    }
    
    [super checkForUpdatesAtURL:URL host:aHost];

    // For background applications, obtain focus.
    // Useful if the update check is requested from another app like System Preferences.
	if (!delegateHandledUpdaterCheck && [aHost isBackgroundApplication])
	{
        [NSApp activateIgnoringOtherApps:YES];
    }
}

- (void)appcastDidFinishLoading:(SUAppcast *)ac
{
	if (self.isCanceled)
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

- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui
{
    // We don't check to see if this update's been skipped, because the user explicitly *asked* if he had the latest version.
    return [self hostSupportsItem:ui] && [self isItemNewer:ui];
}

@end
