//
//  SUProbingUpdateDriver.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/7/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUProbingUpdateDriver.h"
#import "SUUpdaterDelegate.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@implementation SUProbingUpdateDriver

// Stop as soon as we have an answer! Since the superclass implementations are not called, we are responsible for notifying the delegate.

- (void)didFindValidUpdate
{
    if ([self.updaterDelegate respondsToSelector:@selector(updater:didFindValidUpdate:)])
        [self.updaterDelegate updater:self.updater didFindValidUpdate:self.updateItem];
    NSDictionary *userInfo = (self.updateItem != nil) ? @{ SUUpdaterAppcastItemNotificationKey: self.updateItem } : nil;
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidFindValidUpdateNotification object:self.updater userInfo:userInfo];
    [self abortUpdate];
}

- (void)didNotFindUpdate
{
    if ([self.updaterDelegate respondsToSelector:@selector(updaterDidNotFindUpdate:)]) {
        [self.updaterDelegate updaterDidNotFindUpdate:self.updater];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:SUUpdaterDidNotFindUpdateNotification object:self.updater];

    [self abortUpdate];
}

@end
