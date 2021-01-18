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
@property (nonatomic, readonly) BOOL customUserDriver;
@property (nonatomic) SPUStandardUserDriver *userDriver;

@end

@implementation SUUpdateSettingsWindowController

@synthesize updater = _updater;
@synthesize customUserDriver = _customUserDriver;
@synthesize userDriver = _userDriver;

- (instancetype)initWithCustomUserDriver:(BOOL)customUserDriver
{
    self = [super init];
    if (self != nil) {
        _customUserDriver = customUserDriver;
    }
    return self;
}

- (NSString *)windowNibName
{
    return NSStringFromClass([self class]);
}

- (void)windowDidLoad
{
    NSBundle *hostBundle = [NSBundle mainBundle];
    NSBundle *applicationBundle = hostBundle;
    
    id<SPUUserDriver> userDriver;
    if (self.customUserDriver) {
        userDriver = [[SUPopUpTitlebarUserDriver alloc] initWithWindow:self.window];
    } else {
        userDriver = [[SPUStandardUserDriver alloc] initWithHostBundle:hostBundle delegate:nil];
    }
    
    self.userDriver = userDriver;
    self.updater = [[SPUUpdater alloc] initWithHostBundle:hostBundle applicationBundle:applicationBundle userDriver:userDriver delegate:nil];
    
    NSError *updaterError = nil;
    if (![self.updater startUpdater:&updaterError]) {
        NSLog(@"Failed to start updater with error: %@", updaterError);
        
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Updater Error";
        alert.informativeText = @"The Updater failed to start. For detailed error information, check the Console.app log.";
        [alert addButtonWithTitle:@"OK"];
        [alert runModal];
    }
}

- (IBAction)checkForUpdates:(id __unused)sender
{
    [self.updater checkForUpdates];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    if (menuItem.action == @selector(checkForUpdates:)) {
        return self.updater.canCheckForUpdates;
    }
    return YES;
}

@end
