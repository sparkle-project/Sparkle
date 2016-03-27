//
//  SURemoteUpdateSettingsWindowController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/2/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SURemoteUpdateSettingsWindowController.h"
#import "TestAppHelperProtocol.h"
#import "SUPopUpTitlebarUserDriver.h"

@interface SURemoteUpdateSettingsWindowController ()

@property (nonatomic) NSXPCConnection *connection;
@property (nonatomic) id<SUStandardUserDriver> userDriver;

@property (nonatomic) IBOutlet NSButton *automaticallyChecksForUpdatesButton;
@property (nonatomic) IBOutlet NSButton *automaticallyDownloadUpdatesButton;
@property (nonatomic) IBOutlet NSButton *sendsSystemProfileButton;
@property (nonatomic) IBOutlet NSTextField *updateCheckIntervalTextField;

@end

@implementation SURemoteUpdateSettingsWindowController

@synthesize connection = _connection;
@synthesize userDriver = _userDriver;
@synthesize automaticallyChecksForUpdatesButton = _automaticallyChecksForUpdatesButton;
@synthesize automaticallyDownloadUpdatesButton = _automaticallyDownloadUpdatesButton;
@synthesize sendsSystemProfileButton = _sendsSystemProfileButton;
@synthesize updateCheckIntervalTextField = _updateCheckIntervalTextField;

#pragma mark Birth

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        [self setUpConnection];
    }
    return self;
}

- (void)dealloc
{
    [self.connection invalidate];
    self.connection = nil;
}

- (NSString *)windowNibName
{
    return NSStringFromClass([self class]);
}

- (void)reloadSettings
{
    SUUpdaterSettings *settings = [[SUUpdaterSettings alloc] initWithHostBundle:[NSBundle mainBundle]];
    
    // Make sure window is loaded
    [self window];
    
    self.automaticallyChecksForUpdatesButton.state = settings.automaticallyChecksForUpdates ? NSOnState : NSOffState;
    self.automaticallyDownloadUpdatesButton.state = settings.automaticallyDownloadsUpdates ? NSOnState : NSOffState;
    self.sendsSystemProfileButton.state = settings.sendsSystemProfile ? NSOnState : NSOffState;
    self.updateCheckIntervalTextField.doubleValue = settings.updateCheckInterval;
}

- (void)windowDidLoad
{
    [self reloadSettings];
}

- (void)setUpConnection
{
    self.connection = [[NSXPCConnection alloc] initWithServiceName:@"org.sparkle-project.TestAppHelper"];
    
    self.connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUUserDriver)];
    
    //self.userDriver = [[SUPopUpTitlebarUserDriver alloc] initWithWindow:self.window delegate:self];
    self.userDriver = [[SUStandardUserDriver alloc] initWithHostBundle:[NSBundle mainBundle] delegate:self];
    
    self.connection.exportedObject = self.userDriver;
    
    self.connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(TestAppHelperProtocol)];
    
    __weak SURemoteUpdateSettingsWindowController *weakSelf = self;
    
    // Try killing the TestAppHelper process to test this (might not want a debugger attached)
    self.connection.interruptionHandler = ^{
        NSLog(@"Connection is interrupted..!");
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Attempt to do work only if we haven't terminated yet
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!weakSelf.userDriver.willInitiateNextUpdateCheck) {
                    NSLog(@"Invalidating installation..");
                    [weakSelf.userDriver invalidate];
                }
                
                // No need to do anything if we will be sending a message later anyway
                // or if we won't have to send a message immediately anyway
                if (!weakSelf.userDriver.willInitiateNextUpdateCheck && !weakSelf.userDriver.idlesOnUpdateChecks) {
                    NSLog(@"Starting up Sparkle again");
                    [weakSelf.connection.remoteObjectProxy startSparkle];
                } else {
                    NSLog(@"Update checker is in progress or doesn't have to be; no need to panic");
                }
            });
        });
    };
    
    // Try testing this by using the Invalidate Connection menu item
    self.connection.invalidationHandler = ^{
        const uint64_t delay = 60;
        NSLog(@"Connection is invalidated! Rebooting connection in %llu seconds..", delay);
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // Attempt to do work only if we haven't terminated yet
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.userDriver invalidate];
                
                weakSelf.userDriver = nil;
                weakSelf.connection = nil;
                
                // Because the connection was invalidated, it might mean creating a new one will not be easy, so let's wait a bit in our example
                // (Unless the user forces the connection to be created again in our test app, by eg, playing around with the checkboxes)
                // Note this is probably a "dumb" implementation. Perhaps a better one increases the time exponentially on each re-try until a certain limit is reached
                // And that could be cleared out after a certain amount of idle time. Plenty of ways to approach this..
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    NSLog(@"Rebooting connection..");
                    if (weakSelf != nil && weakSelf.connection == nil) {
                        [weakSelf setUpConnection];
                        [weakSelf reloadSettings];
                    }
                });
            });
        });
    };
    
    [self.connection resume];
    [self.connection.remoteObjectProxy startSparkle];
}

#pragma mark UI Actions
// When the user explicitly checks for updates via the menu item..
- (IBAction)checkForUpdates:(id)__unused sender
{
    [self.connection.remoteObjectProxy initiateUserCheckForUpdates];
}

// See if the user is allowed to invoke the check for update's menu item's action
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    if (menuItem.action == @selector(checkForUpdates:)) {
        return (self.userDriver != nil && !self.userDriver.updateInProgress);
    } else if (menuItem.action == @selector(invalidateConnection:)) {
        return (self.connection != nil);
    }
    return YES;
}

- (IBAction)invalidateConnection:(id)__unused sender
{
    [self.connection invalidate];
}

#pragma mark Changing Settings

- (IBAction)changeAutomaticallyChecksForUpdates:(__unused id)sender
{
    [self.connection.remoteObjectProxy setAutomaticallyChecksForUpdates:self.automaticallyChecksForUpdatesButton.state == NSOnState];
}

- (IBAction)changeAutomaticallyDownloadsUpdates:(__unused id)sender
{
    [self.connection.remoteObjectProxy setAutomaticallyDownloadsUpdates:self.automaticallyDownloadUpdatesButton.state == NSOnState];
}

- (IBAction)changeSendsSystemProfile:(__unused id)sender
{
    [self.connection.remoteObjectProxy setSendsSystemProfile:self.sendsSystemProfileButton.state == NSOnState];
}

- (IBAction)changeUpdateCheckInterval:(__unused id)sender
{
    [self.connection.remoteObjectProxy setUpdateCheckInterval:self.updateCheckIntervalTextField.doubleValue];
}

#pragma mark Update Checks

- (BOOL)responsibleForInitiatingUpdateCheck
{
    return YES;
}

- (void)initiateUpdateCheck
{
    [self.connection.remoteObjectProxy checkForUpdates];
}

@end
