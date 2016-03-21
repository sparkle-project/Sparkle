//
//  SUPopUpTitlebarUserDriver.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/5/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUPopUpTitlebarUserDriver.h"
#import "SUStandardUserDriverDelegate.h"
#import "SUUserDriverCoreComponent.h"
#import "SUInstallUpdateViewController.h"

@interface SUPopUpTitlebarUserDriver()

@property (nonatomic, readonly) NSWindow *window;
@property (nonatomic, readonly) SUUserDriverCoreComponent *coreComponent;
@property (nonatomic) NSTitlebarAccessoryViewController *accessoryViewController;
@property (nonatomic) BOOL addedAccessory;
@property (nonatomic) NSButton *updateButton;
@property (nonatomic, copy) void (^updateButtonAction)(NSButton *);
@property (nonatomic) NSUInteger expectedContentLength;
@property (nonatomic) NSUInteger contentLengthDownloaded;

@end

@implementation SUPopUpTitlebarUserDriver

@synthesize delegate = _delegate;
@synthesize window = _window;
@synthesize coreComponent = _coreComponent;
@synthesize accessoryViewController = _accessoryViewController;
@synthesize addedAccessory = _addedAccessory;
@synthesize updateButton = _updateButton;
@synthesize updateButtonAction = _updateButtonAction;
@synthesize expectedContentLength = _expectedContentLength;
@synthesize contentLengthDownloaded = _contentLengthDownloaded;

- (instancetype)initWithWindow:(NSWindow *)window delegate:(id<SUStandardUserDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _window = window;
        _delegate = delegate;
        _coreComponent = [[SUUserDriverCoreComponent alloc] initWithDelegate:delegate];
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

#pragma mark Is Update Busy?

- (void)idleOnUpdateChecks:(BOOL)shouldIdleOnUpdateChecks
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent idleOnUpdateChecks:shouldIdleOnUpdateChecks];
    });
}

- (BOOL)idlesOnUpdateChecks
{
    return self.coreComponent.idlesOnUpdateChecks;
}

- (void)showUpdateInProgress:(BOOL)isUpdateInProgress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent showUpdateInProgress:isUpdateInProgress];
    });
}

- (BOOL)isUpdateInProgress
{
    return self.coreComponent.updateInProgress;
}

#pragma mark Check Updates Timer

- (BOOL)willInitiateNextUpdateCheck
{
    return [self.coreComponent willInitiateNextUpdateCheck];
}

- (void)startUpdateCheckTimerWithNextTimeInterval:(NSTimeInterval)timeInterval reply:(void (^)(SUUpdateCheckTimerStatus))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent startUpdateCheckTimerWithNextTimeInterval:timeInterval reply:reply];
    });
}

- (void)invalidateUpdateCheckTimer
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent invalidateUpdateCheckTimer];
    });
}

#pragma mark Update Permission

- (void)requestUpdatePermissionWithSystemProfile:(NSArray *)__unused systemProfile reply:(void (^)(SUUpdatePermissionPromptResult *))reply
{
    // Just make a decision..
    dispatch_async(dispatch_get_main_queue(), ^{
        reply([SUUpdatePermissionPromptResult updatePermissionPromptResultWithChoice:SUAutomaticallyCheck shouldSendProfile:NO]);
    });
}

#pragma mark Update Found

- (void)showUpdateWithAppcastItem:(SUAppcastItem *)appcastItem alreadyDownloaded:(BOOL)alreadyDownloaded reply:(void (^)(SUUpdateAlertChoice))reply
{
    NSPopover *popover = [[NSPopover alloc] init];
    popover.behavior = NSPopoverBehaviorTransient;
    
    [self addUpdateButtonWithTitle:@"Update Available" action:^(NSButton *button) {
        if (popover.contentViewController == nil) {
            popover.contentViewController = [[SUInstallUpdateViewController alloc] initWithAppcastItem:appcastItem alreadyDownloaded:alreadyDownloaded reply:^(SUUpdateAlertChoice choice) {
                reply(choice);
                
                [popover close];
                button.enabled = NO;
            }];
        }
        
        [popover showRelativeToRect:button.bounds ofView:button preferredEdge:NSMaxYEdge];
    }];
}

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem allowsAutomaticUpdates:(BOOL)__unused allowsAutomaticUpdates alreadyDownloaded:(BOOL)alreadyDownloaded reply:(void (^)(SUUpdateAlertChoice))reply
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self showUpdateWithAppcastItem:appcastItem alreadyDownloaded:alreadyDownloaded reply:reply];
    });
}

#pragma mark Install & Relaunch Update

- (void)showExtractionFinishedAndReadyToInstallAndRelaunch:(void (^)(SUInstallUpdateStatus))installUpdateHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent registerInstallUpdateHandler:installUpdateHandler];
        
        [self addUpdateButtonWithTitle:@"Install & Relaunch" action:^(NSButton *__unused button) {
            installUpdateHandler(SUInstallAndRelaunchUpdateNow);
        }];
    });
}

#pragma mark Check for Updates

- (void)showUserInitiatedUpdateCheckWithCompletion:(void (^)(SUUserInitiatedCheckStatus))updateCheckStatusCompletion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent registerUpdateCheckStatusHandler:updateCheckStatusCompletion];
        
        [self addUpdateButtonWithTitle:@"Checking for Updates…"];
    });
}

- (void)dismissUserInitiatedUpdateCheck
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent completeUpdateCheckStatus];
        [self removeUpdateButton];
    });
}

#pragma mark Update Errors

- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent registerAcknowledgement:acknowledgement];
        
        NSLog(@"Error: %@", error);
        [self addUpdateButtonWithTitle:@"Update Errored!" action:nil];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // Installation will be dismissed shortly after this
            [self.coreComponent acceptAcknowledgement];
        });
    });
}

- (void)showUpdateNotFoundWithAcknowledgement:(void (^)(void))acknowledgement
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent registerAcknowledgement:acknowledgement];
        
        [self addUpdateButtonWithTitle:@"No Update Available" action:nil];
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            // Installation will be dismissed shortly after this
            [self.coreComponent acceptAcknowledgement];
        });
    });
}

#pragma mark Download & Install Updates

- (void)showDownloadInitiatedWithCompletion:(void (^)(SUDownloadUpdateStatus))downloadUpdateStatusCompletion
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent registerDownloadStatusHandler:downloadUpdateStatusCompletion];
    });
}

- (void)showDownloadDidReceiveResponse:(NSURLResponse *)response
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self addUpdateButtonWithTitle:@"Downloading…"];
        self.contentLengthDownloaded = 0;
        self.expectedContentLength = (NSUInteger)response.expectedContentLength;
        if (self.expectedContentLength == 0) {
            // don't divide by zero ever
            self.expectedContentLength = 1;
        }
    });
}

- (void)showDownloadDidReceiveDataOfLength:(NSUInteger)length
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.contentLengthDownloaded += length;
        double progress = (double)self.contentLengthDownloaded / self.expectedContentLength;
        [self addUpdateButtonWithTitle:[NSString stringWithFormat:@"Downloading (%d%%)", (int)progress] action:nil];
    });
}

- (void)showDownloadFinishedAndStartedExtractingUpdate
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.coreComponent completeDownloadStatus];
        [self addUpdateButtonWithTitle:@"Extracting…"];
    });
}

- (void)showExtractionReceivedProgress:(double)progress
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self addUpdateButtonWithTitle:[NSString stringWithFormat:@"Extracting (%d%%)…", (int)(progress * 100)]];
    });
}

- (void)showInstallingUpdate
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self addUpdateButtonWithTitle:@"Installing…"];
    });
}

#pragma mark Aborting Everything

- (void)terminateApplication
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSApplication sharedApplication] terminate:nil];
    });
}

- (void)_dismissUpdateInstallation
{
    // Make sure everything we call here does not dispatch async to main queue
    // because we are already on the main queue (and I've been bitten in the past by this before)
    
    [self.coreComponent dismissUpdateInstallation];
    
    [self removeUpdateButton];
}

- (void)dismissUpdateInstallation
{
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _dismissUpdateInstallation];
    });
}

- (void)invalidate
{
    [self.coreComponent invalidate];
    
    [self _dismissUpdateInstallation];
}

@end
