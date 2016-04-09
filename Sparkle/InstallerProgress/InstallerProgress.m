//
//  InstallerProgress.m
//  Installer Progress
//
//  Created by Mayur Pawashe on 4/7/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SURemoteMessagePort.h"
#import "SUMessageTypes.h"
#import "SUStatusController.h"
#import "SUHost.h"
#import "SULocalizations.h"
#import "SULog.h"

/*!
 * Terminate the application after a delay from launching the new update to avoid OS activation issues
 * This delay should be be high enough to increase the likelihood that our updated app will be launched up front,
 * but should be low enough so that the user doesn't ponder why the updater hasn't finished terminating yet
 */
static const NSTimeInterval SUTerminationTimeDelay = 0.3;

@interface InstallerProgress : NSObject <NSApplicationDelegate>

@property (nonatomic, readonly) SURemoteMessagePort *remotePort;
@property (nonatomic) SUStatusController *statusController;

@end

@implementation InstallerProgress

@synthesize remotePort = _remotePort;
@synthesize statusController = _statusController;

- (instancetype)initWithHost:(SUHost *)host
{
    self = [super init];
    if (self != nil) {
        NSString *bundleIdentifier = host.bundle.bundleIdentifier;
        if (bundleIdentifier == nil) {
            SULog(@"Error: Bundle Identifier for host is nil");
            exit(0);
        }
        
        _remotePort = [[SURemoteMessagePort alloc] initWithServiceName:SUAutoUpdateServiceNameForBundleIdentifier(bundleIdentifier)];
        _statusController = [[SUStatusController alloc] initWithHost:host];
    }
    return self;
}

// Close status window immediately, but delay termination for a little bit to better increase the chance
// the updated application when relaunched will be the frontmost application
// This is related to OS X activation issues when terminating a frontmost application happens right before
// launching another app
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SUTerminationTimeDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [sender replyToApplicationShouldTerminate:YES];
    });
    
    [self.statusController close];
    self.statusController = nil;
    
    return NSTerminateLater;
}

- (void)applicationDidFinishLaunching:(NSNotification *)__unused notification
{
    __weak InstallerProgress *weakSelf = self;
    [self.remotePort connectWithLookupCompletion:^(BOOL success) {
        if (!success) {
            [NSApp terminate:nil];
        } else {
            [weakSelf.remotePort setInvalidationHandler:^{
                [NSApp terminate:nil];
            }];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf showInstallerProgress];
            });
        }
    }];
}

- (void)showInstallerProgress
{
    [self.statusController setButtonTitle:SULocalizedString(@"Cancel Update", @"") target:nil action:nil isDefault:NO];
    [self.statusController beginActionWithTitle:SULocalizedString(@"Installing update...", @"") maxProgressValue:0 statusText:@""];
    [self.statusController showWindow:self];
}

@end

int main(int __unused argc, const char __unused *argv[])
{
    @autoreleasepool
    {
        NSArray *args = [[NSProcessInfo processInfo] arguments];
        if (args.count < 2) {
            return EXIT_FAILURE;
        }
        
        NSString *hostBundlePath = args[1];
        
        NSImage *applicationIcon = nil;
        if (args.count > 2) {
            applicationIcon = [[NSImage alloc] initWithContentsOfFile:args[2]];
        }
        
        NSBundle *bundle = [NSBundle bundleWithPath:hostBundlePath];
        if (bundle == nil) {
            SULog(@"Error: bundle at %@ is nil", hostBundlePath);
            return EXIT_FAILURE;
        }
        
        SUHost *host = [[SUHost alloc] initWithBundle:bundle];
        InstallerProgress *delegate = [[InstallerProgress alloc] initWithHost:host];
        
        NSApplication *application = [NSApplication sharedApplication];
        
        if (applicationIcon != nil) {
            application.applicationIconImage = applicationIcon;
        }
        
        [application setDelegate:delegate];
        
        [application run];
    }
    
    return EXIT_SUCCESS;
}
