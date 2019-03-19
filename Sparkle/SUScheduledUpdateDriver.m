//
//  SUScheduledUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/6/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUScheduledUpdateDriver.h"
#import "SUUpdaterPrivate.h"
#import "SUUpdaterDelegate.h"

#import "SUHost.h"
#import "SUSystemUpdateInfo.h"
#import "SUAppcastItem.h"
#import "SUConstants.h"

@interface SUScheduledUpdateDriver ()

@end

@implementation SUScheduledUpdateDriver

- (instancetype)initWithUpdater:(id<SUUpdaterPrivate>)anUpdater
{
    if ((self = [super initWithUpdater:anUpdater])) {
        self.showErrors = NO;
    }
    return self;
}

- (NSUInteger)numUpdateGroups {
    NSNumber *value = [self.host objectForKey:SUNumUpdateGroupsKey];
    if (value)
        return [value unsignedIntegerValue];
    else
        return SUDefaultNumUpdateGroups;
}

- (NSTimeInterval)updateGroupInterval {
    NSNumber *intervalValue = [self.host objectForKey:SUUpdateGroupIntervalKey];
    if (intervalValue)
        return [intervalValue doubleValue];
    else
        return SUDefaultUpdateGroupInterval;
}

- (BOOL)itemContainsValidUpdate:(SUAppcastItem *)ui {
    return [self isItemReadyForUpdateGroup:ui] && [super itemContainsValidUpdate:ui];
}

- (BOOL)isItemReadyForUpdateGroup:(SUAppcastItem *)ui {
    [self.host objectForKey:SUNumUpdateGroupsKey];

    if([ui isCriticalUpdate] || [self numUpdateGroups] < 2) {
        return YES;
    }

    NSDate* itemReleaseDate = ui.date;
    if(itemReleaseDate) {
        NSTimeInterval timeSinceRelease = [[NSDate date] timeIntervalSinceDate:itemReleaseDate];
        NSTimeInterval timeToWaitForGroup = [self updateGroupInterval] * [SUSystemUpdateInfo updateGroupForHost:self.host];

        if(timeSinceRelease < timeToWaitForGroup) {
            return NO; // not this host's turn yet
        }
    }

    return YES;
}

- (void)didFindValidUpdate
{
    self.showErrors = YES; // We only start showing errors after we present the UI for the first time.
    [super didFindValidUpdate];
}

- (void)didNotFindUpdate
{
    id<SUUpdaterPrivate> updater = self.updater;
    id<SUUpdaterDelegate> updaterDelegate = [updater delegate];

    if ([updaterDelegate respondsToSelector:@selector(updaterDidNotFindUpdate:)]) {
        [updaterDelegate updaterDidNotFindUpdate:self.updater];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidNotFindUpdateNotification object:self.updater];

    [self abortUpdate]; // Don't tell the user that no update was found; this was a scheduled update.
}

- (BOOL)shouldDisableKeyboardShortcutForInstallButton {
    return YES;
}

- (BOOL)shouldShowUpdateAlertForItem:(SUAppcastItem *)item {
    id<SUUpdaterPrivate> updater = self.updater;
    id<SUUpdaterDelegate> updaterDelegate = [updater delegate];

    if ([updaterDelegate respondsToSelector:@selector(updaterShouldShowUpdateAlertForScheduledUpdate:forItem:)]) {
        return [updaterDelegate updaterShouldShowUpdateAlertForScheduledUpdate:self.updater forItem:item];
    }

    return [super shouldShowUpdateAlertForItem:item];
}

@end
