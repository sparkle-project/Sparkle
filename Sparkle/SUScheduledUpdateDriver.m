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

@end
