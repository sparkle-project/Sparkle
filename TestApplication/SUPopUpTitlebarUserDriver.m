//
//  SUPopUpTitlebarUserDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/5/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUPopUpTitlebarUserDriver.h"
#import "SUInstallUpdateViewController.h"
#import <AppKit/AppKit.h>

@interface SUPopUpTitlebarUserDriver()

@property (nonatomic, readonly) NSWindow *window;
@property (nonatomic, nullable) SUInstallUpdateViewController *installUpdateViewController;
@property (nonatomic) NSTitlebarAccessoryViewController *accessoryViewController;
@property (nonatomic) BOOL addedAccessory;
@property (nonatomic) NSButton *updateButton;
@property (nonatomic, copy) void (^updateButtonAction)(NSButton *);
@property (nonatomic) uint64_t expectedContentLength;
@property (nonatomic) uint64_t contentLengthDownloaded;

@end

@implementation SUPopUpTitlebarUserDriver

@synthesize window = _window;
@synthesize installUpdateViewController = _installUpdateViewController;
@synthesize accessoryViewController = _accessoryViewController;
@synthesize addedAccessory = _addedAccessory;
@synthesize updateButton = _updateButton;
@synthesize updateButtonAction = _updateButtonAction;
@synthesize expectedContentLength = _expectedContentLength;
@synthesize contentLengthDownloaded = _contentLengthDownloaded;

- (instancetype)initWithWindow:(NSWindow *)window
{
    self = [super init];
    if (self != nil) {
        _window = window;
    }
    return self;
}

- (void)addUpdateButtonWithTitle:(NSString *)title
{
    [self addUpdateButtonWithTitle:title action:nil];
}

- (void)addUpdateButtonWithTitle:(NSString *)title action:(void (^)(NSButton *button))action
{
    if (self.updateButton == nil) {
        NSButton *updateButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 160, 100)];
        updateButton.title = title;
        updateButton.bezelStyle = NSRecessedBezelStyle;
        
        self.updateButton = updateButton;
    } else {
        self.updateButton.title = title;
    }
    
    if (action != nil) {
        self.updateButton.target = self;
        self.updateButton.action = @selector(updateButtonAction:);
        self.updateButtonAction = action;
        self.updateButton.enabled = YES;
    } else {
        self.updateButton.enabled = NO;
        self.updateButton.target = nil;
        self.updateButtonAction = nil;
    }
    
    if (self.accessoryViewController == nil) {
        self.accessoryViewController = [[NSTitlebarAccessoryViewController alloc] init];
        self.accessoryViewController.layoutAttribute = NSLayoutAttributeRight;
        self.accessoryViewController.view = self.updateButton;
    }
    
    if (!self.addedAccessory) {
        [self.window addTitlebarAccessoryViewController:self.accessoryViewController];
        self.addedAccessory = YES;
    }
}

- (void)updateButtonAction:(NSButton *)sender
{
    if (self.updateButtonAction != nil) {
        self.updateButtonAction(sender);
    }
}

- (void)removeUpdateButton
{
    [self.accessoryViewController removeFromParentViewController];
    self.addedAccessory = NO;
    self.updateButtonAction = nil;
}

#pragma mark Update Permission

- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)__unused request reply:(void (^)(SUUpdatePermissionResponse *))reply
{
    // Just make a decision..
    SUUpdatePermissionResponse *response = [[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:YES sendSystemProfile:NO];
    reply(response);
}

#pragma mark Update Found

- (void)showUpdateWithAppcastItem:(SUAppcastItem *)appcastItem reply:(void (^)(SPUUserUpdateChoice))reply
{
    NSPopover *popover = [[NSPopover alloc] init];
    popover.behavior = NSPopoverBehaviorTransient;
    
    __weak SUPopUpTitlebarUserDriver *weakSelf = self;
    __block NSButton *actionButton = nil;
    
    SUInstallUpdateViewController *viewController = [[SUInstallUpdateViewController alloc] initWithAppcastItem:appcastItem reply:^(SPUUserUpdateChoice choice) {
        reply(choice);
        
        [popover close];
        actionButton.enabled = NO;
        
        weakSelf.installUpdateViewController = nil;
    }];
    
    self.installUpdateViewController = viewController;
    
    [self addUpdateButtonWithTitle:@"Update Available" action:^(NSButton *button) {
        actionButton = button;
        popover.contentViewController = viewController;
        [popover showRelativeToRect:button.bounds ofView:button preferredEdge:NSMaxYEdge];
    }];
}

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply
{
    if (appcastItem.informationOnlyUpdate) {
        // Todo: show user interface for this
        NSLog(@"Found info URL: %@", appcastItem.infoURL);
        
        // Remove UI from user initiated check
        [self removeUpdateButton];
        
        reply(SPUUserUpdateChoiceDismiss);
    } else {
        [self showUpdateWithAppcastItem:appcastItem reply:reply];
    }
}

- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData
{
    [self.installUpdateViewController showReleaseNotesWithDownloadData:downloadData];
}

- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)__unused error
{
}

- (void)showUpdateInFocus
{
    [self.window makeKeyAndOrderFront:nil];
    
    if (self.updateButton.enabled) {
        // Not the proper way to do things but ignoring warnings in Test App.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-messaging-id"
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [self.updateButton.target performSelector:self.updateButton.action withObject:self.updateButton];
#pragma clang diagnostic pop
    }
}

#pragma mark Install & Relaunch Update

- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))installUpdateHandler
{
    [self addUpdateButtonWithTitle:@"Install & Relaunch" action:^(NSButton *__unused button) {
        installUpdateHandler(SPUUserUpdateChoiceInstall);
    }];
}

#pragma mark Check for Updates

- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))__unused cancellation
{
    [self addUpdateButtonWithTitle:@"Checking for Updates…"];
}

#pragma mark Update Errors

- (void)acceptAcknowledgementAfterDelay:(void (^)(void))acknowledgement
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Installation will be dismissed shortly after this
        acknowledgement();
    });
}

- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement
{
    NSLog(@"Error: %@", error);
    [self addUpdateButtonWithTitle:@"Update Errored!" action:nil];
    
    [self acceptAcknowledgementAfterDelay:acknowledgement];
}

- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement
{
    [self addUpdateButtonWithTitle:@"No Update Available" action:nil];
    
    [self acceptAcknowledgementAfterDelay:acknowledgement];
}

#pragma mark Download & Install Updates

- (void)showDownloadInitiatedWithCancellation:(void (^)(void))__unused cancellation
{
}

- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)expectedContentLength
{
    [self addUpdateButtonWithTitle:@"Downloading…"];
    self.contentLengthDownloaded = 0;
    self.expectedContentLength = expectedContentLength;
}

- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length
{
    self.contentLengthDownloaded += length;
    
    // In case our expected content length was incorrect
    if (self.contentLengthDownloaded > self.expectedContentLength) {
        self.expectedContentLength = self.contentLengthDownloaded;
    }
    
    if (self.expectedContentLength > 0) {
        double progress = (double)self.contentLengthDownloaded / self.expectedContentLength;
        [self addUpdateButtonWithTitle:[NSString stringWithFormat:@"Downloading (%0.0f%%)", progress * 100] action:nil];
    }
}

- (void)showDownloadDidStartExtractingUpdate
{
    [self addUpdateButtonWithTitle:@"Extracting…"];
}

- (void)showExtractionReceivedProgress:(double)progress
{
    [self addUpdateButtonWithTitle:[NSString stringWithFormat:@"Extracting (%d%%)…", (int)(progress * 100)]];
}

- (void)showInstallingUpdate
{
    [self addUpdateButtonWithTitle:@"Installing…"];
}

- (void)showSendingTerminationSignal
{
    // In case our termination request fails or is delayed
    [self removeUpdateButton];
}

- (void)showUpdateInstalledAndRelaunched:(BOOL)__unused relaunched acknowledgement:(void (^)(void))acknowledgement
{
    [self addUpdateButtonWithTitle:@"Installation Finished!"];
    
    [self acceptAcknowledgementAfterDelay:acknowledgement];
}

#pragma mark Aborting Everything

- (void)dismissUpdateInstallation
{
    [self removeUpdateButton];
}

@end
