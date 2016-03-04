//
//  SURemoteUpdateSettingsWindowController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/2/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SURemoteUpdateSettingsWindowController.h"
#import "TestAppHelperProtocol.h"

@interface SURemoteUpdateSettingsWindowController ()

@property (nonatomic) NSXPCConnection *connection;
@property (nonatomic) SUStandardUserDriver *userDriver;

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

- (NSString *)windowNibName
{
    return NSStringFromClass([self class]);
}

- (void)setUpConnection
{
    self.connection = [[NSXPCConnection alloc] initWithServiceName:@"org.sparkle-project.TestAppHelper"];
    
    self.connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUUserDriver)];
    self.userDriver = [[SUStandardUserDriver alloc] initWithHostBundle:[NSBundle mainBundle] delegate:self];
    self.connection.exportedObject = self.userDriver;
    
    self.connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(TestAppHelperProtocol)];
    
    __weak SURemoteUpdateSettingsWindowController *weakSelf = self;
    
    // Try killing the TestAppHelper process to test this (might not want a debugger attached)
    self.connection.interruptionHandler = ^{
        NSLog(@"Connection is interrupted! Sending another message to get it back..");
        
        // This method dispatches on the main queue
        [weakSelf.userDriver dismissUpdateInstallation];
        
        // I want this to be sent after dismissing update installation is done
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.connection.remoteObjectProxy startSparkle];
        });
    };
    
    // Try testing this by using the Invalidate Connection menu item
    self.connection.invalidationHandler = ^{
        const uint64_t delay = 10;
        NSLog(@"Connection is invalidated! Rebooting connection in %llu seconds..", delay);
        
        // This method dispatches on the main queue
        [weakSelf.userDriver dismissUpdateInstallation];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.userDriver = nil;
            weakSelf.connection = nil;
            
            // This must be called on main queue
            // Because the connection was invalidated, it might mean creating a new one will not be easy, so let's wait a bit in our example
            // Note this is a "stupid" implementation. Perhaps a better one increases the time exponentially on each re-try until a certain limit is reached
            // And that could be cleared out after a certain amount of idle time. Would require some thinking.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                NSLog(@"Rebooting connection..");
                [weakSelf setUpConnection];
            });
        });
    };
    
    [self.connection resume];
    [self.connection.remoteObjectProxy startSparkle];
    
    // Retrieving the settings really takes a while, perhaps a smarter app may also store defaults locally and sync them
    [self.connection.remoteObjectProxy retrieveUpdateSettings:^(BOOL automaticallyCheckForUpdates, BOOL automaticallyDownloadUpdates, BOOL sendSystemProfile, NSTimeInterval updateCheckInterval) {
        dispatch_async(dispatch_get_main_queue(), ^{
            // Load the window before referencing our outlets
            [self window];
            
            self.automaticallyChecksForUpdatesButton.state = automaticallyCheckForUpdates ? NSOnState : NSOffState;
            self.automaticallyDownloadUpdatesButton.state = automaticallyDownloadUpdates ? NSOnState : NSOffState;
            self.sendsSystemProfileButton.state = sendSystemProfile ? NSOnState : NSOffState;
            self.updateCheckIntervalTextField.doubleValue = updateCheckInterval;
            
            // Ready to show our window
            if (!self.window.isVisible) {
                [self showWindow:nil];
            }
        });
    }];
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

#pragma mark App Termination

- (BOOL)responsibleForSignalingApplicationTerminationForUserDriver:(id <SUUserDriver>)__unused userDriver
{
    return YES;
}

- (NSApplicationTerminateReply)sendTerminationSignal
{
    return [self.userDriver sendApplicationTerminationSignal];
}

#pragma mark Update Checks

- (BOOL)responsibleForInitiatingUpdateCheckForUserDriver:(id <SUUserDriver>)__unused userDriver
{
    return YES;
}

- (void)initiateUpdateCheckForUserDriver:(id <SUUserDriver>)__unused userDriver
{
    [self.connection.remoteObjectProxy checkForUpdates];
}

@end
