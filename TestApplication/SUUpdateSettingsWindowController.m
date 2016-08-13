//
//  SUUpdateSettingsWindowController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 7/25/15.
//  Copyright (c) 2015 Sparkle Project. All rights reserved.
//

#import "SUUpdateSettingsWindowController.h"
#import <Sparkle/Sparkle.h>
#import "SUPopUpTitlebarUserDriver.h"

@interface SUUpdateSettingsWindowController ()

@property (nonatomic) SPUUpdater *updater;
@property (nonatomic) id<SPUStandardUserDriverProtocol> userDriver;

@end

@implementation SUUpdateSettingsWindowController

@synthesize updater = _updater;
@synthesize userDriver = _userDriver;

- (NSString *)windowNibName
{
    return NSStringFromClass([self class]);
}

- (void)windowDidLoad
{
    NSBundle *hostBundle = [NSBundle mainBundle];
    
    // If the user is holding down command, we use the popup title user driver instead
    id<SPUUserDriver, SPUStandardUserDriverProtocol> userDriver;
    if (([NSEvent modifierFlags] & NSCommandKeyMask) != 0) {
        userDriver = [[SUPopUpTitlebarUserDriver alloc] initWithHostBundle:hostBundle window:self.window];
    } else {
        userDriver = [[SPUStandardUserDriver alloc] initWithHostBundle:hostBundle delegate:nil];
    }
    
    self.userDriver = userDriver;
    self.updater = [[SPUUpdater alloc] initWithHostBundle:hostBundle userDriver:userDriver delegate:nil];
    
    NSError *updaterError = nil;
    if (![self.updater startUpdater:&updaterError]) {
        NSLog(@"Failed to start updater with error: %@", updaterError);
        abort();
    }
}

- (IBAction)checkForUpdates:(id __unused)sender
{
    [self.updater checkForUpdates];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    if (menuItem.action == @selector(checkForUpdates:)) {
        return self.userDriver.canCheckForUpdates;
    }
    return YES;
}

@end
