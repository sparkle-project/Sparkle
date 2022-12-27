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

@implementation SUPopUpTitlebarUserDriver
{
    void (^_updateButtonAction)(NSButton *);
    
    NSWindow *_window;
    SUInstallUpdateViewController *_installUpdateViewController;
    NSTitlebarAccessoryViewController *_accessoryViewController;
    NSButton *_updateButton;
    
    uint64_t _expectedContentLength;
    uint64_t _contentLengthDownloaded;
    
    BOOL _addedAccessory;
}

- (instancetype)initWithWindow:(NSWindow *)window
{
    self = [super init];
    if (self != nil) {
        _window = window;
    }
    return self;
}

- (void)addUpdateButtonWithTitle:(NSString *)title SPU_OBJC_DIRECT
{
    [self addUpdateButtonWithTitle:title action:nil];
}

- (void)addUpdateButtonWithTitle:(NSString *)title action:(void (^)(NSButton *button))action SPU_OBJC_DIRECT
{
    if (_updateButton == nil) {
        NSButton *updateButton = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 160, 100)];
        updateButton.title = title;
        updateButton.bezelStyle = NSBezelStyleRecessed;
        
        _updateButton = updateButton;
    } else {
        _updateButton.title = title;
    }
    
    if (action != nil) {
        _updateButton.target = self;
        _updateButton.action = @selector(updateButtonAction:);
        _updateButtonAction = action;
        _updateButton.enabled = YES;
    } else {
        _updateButton.enabled = NO;
        _updateButton.target = nil;
        _updateButtonAction = nil;
    }
    
    if (_accessoryViewController == nil) {
        _accessoryViewController = [[NSTitlebarAccessoryViewController alloc] init];
        _accessoryViewController.layoutAttribute = NSLayoutAttributeRight;
        _accessoryViewController.view = _updateButton;
    }
    
    if (!_addedAccessory) {
        [_window addTitlebarAccessoryViewController:_accessoryViewController];
        _addedAccessory = YES;
    }
}

- (void)updateButtonAction:(NSButton *)sender
{
    if (_updateButtonAction != nil) {
        _updateButtonAction(sender);
    }
}

- (void)removeUpdateButton SPU_OBJC_DIRECT
{
    [_accessoryViewController removeFromParentViewController];
    _addedAccessory = NO;
    _updateButtonAction = nil;
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
    
    __weak __typeof__(self) weakSelf = self;
    __block NSButton *actionButton = nil;
    
    SUInstallUpdateViewController *viewController = [[SUInstallUpdateViewController alloc] initWithAppcastItem:appcastItem reply:^(SPUUserUpdateChoice choice) {
        reply(choice);
        
        [popover close];
        actionButton.enabled = NO;
        
        __typeof__(self) strongSelf = weakSelf;
        if (strongSelf != nil) {
            strongSelf->_installUpdateViewController = nil;
        }
    }];
    
    _installUpdateViewController = viewController;
    
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
    [_installUpdateViewController showReleaseNotesWithDownloadData:downloadData];
}

- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)__unused error
{
}

- (void)showUpdateInFocus
{
    [_window makeKeyAndOrderFront:nil];
    
    if (_updateButton.enabled) {
        // Not the proper way to do things but ignoring warnings in Test App.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-messaging-id"
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [_updateButton.target performSelector:_updateButton.action withObject:_updateButton];
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
    _contentLengthDownloaded = 0;
    _expectedContentLength = expectedContentLength;
}

- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length
{
    _contentLengthDownloaded += length;
    
    // In case our expected content length was incorrect
    if (_contentLengthDownloaded > _expectedContentLength) {
        _expectedContentLength = _contentLengthDownloaded;
    }
    
    if (_expectedContentLength > 0) {
        double progress = (double)_contentLengthDownloaded / _expectedContentLength;
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

- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)applicationTerminated retryTerminatingApplication:(void (^)(void))__unused retryTerminatingApplication
{
    if (applicationTerminated) {
        [self addUpdateButtonWithTitle:@"Installing…"];
    } else {
        // In case our termination request fails or is delayed
        [self removeUpdateButton];
    }
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
