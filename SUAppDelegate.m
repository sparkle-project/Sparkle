//
//  SUAppDelegate.m
//  Sparkle
//
//  Created by Dmytro Tretiakov on 8/1/14.
//
//

#import "SUAppDelegate.h"
#import <Sparkle/Sparkle.h>

@implementation SUAppDelegate

- (void)dealloc
{
    self.updater = nil;
    self.updaterQueue = nil;
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    self.updaterQueue = [[[SUUpdaterQueue alloc] init] autorelease];
    [self.updaterQueue addUpdater:self.updater];
}

@end
