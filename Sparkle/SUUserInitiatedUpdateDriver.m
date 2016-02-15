//
//  SUUserInitiatedUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/30/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUUserInitiatedUpdateDriver.h"
#import "SUUpdater.h"
#import "SUHost.h"

@interface SUUserInitiatedUpdateDriver ()

@property (assign, getter=isCanceled) BOOL canceled;

@end

@implementation SUUserInitiatedUpdateDriver

@synthesize canceled;

- (void)closeCheckingWindow
{
    [self.updater.userUpdaterDriver dismissUserInitiatedUpdateCheck];
}

- (void)cancelCheckForUpdates:(id)__unused sender
{
    [self closeCheckingWindow];
    self.canceled = YES;
}

#warning assign user driver's host in a superclass of this method, possibly the UI driver.. IDK
- (void)checkForUpdatesAtURL:(NSURL *)URL host:(SUHost *)aHost
{
    [self.updater.userUpdaterDriver showUserInitiatedUpdateCheckWithCancelCallback:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self cancelCheckForUpdates:nil];
        });
    }];
    
    [super checkForUpdatesAtURL:URL host:aHost];
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
