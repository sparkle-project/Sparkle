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
        self.connection = [[NSXPCConnection alloc] initWithServiceName:@"org.sparkle-project.TestAppHelper"];
        
        self.connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SUUserDriver)];
        self.userDriver = [[SUStandardUserDriver alloc] initWithHostBundle:[NSBundle mainBundle] delegate:self];
        self.connection.exportedObject = self.userDriver;
        
        self.connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(TestAppHelperProtocol)];
        
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
                [self showWindow:nil];
            });
        }];
    }
    return self;
}

- (NSString *)windowNibName
{
    return NSStringFromClass([self class]);
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
        return !self.userDriver.updateInProgress;
    }
    return YES;
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
