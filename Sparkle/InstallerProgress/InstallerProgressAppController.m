//
//  InstallerProgressAppController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "InstallerProgressAppController.h"
#import "InstallerProgressAppControllerDelegate.h"
#import "SUInstallerStatus.h"
#import "SUMessageTypes.h"
#import "SULog.h"
#import "SUApplicationInfo.h"

/*!
 * Terminate the application after a delay from launching the new update to avoid OS activation issues
 * This delay should be be high enough to increase the likelihood that our updated app will be launched up front,
 * but should be low enough so that the user doesn't ponder why the updater hasn't finished terminating yet
 */
static const NSTimeInterval SUTerminationTimeDelay = 0.3;

@interface InstallerProgressAppController () <NSApplicationDelegate>

@property (nonatomic, readonly) NSApplication *application;
@property (nonatomic, readonly) NSBundle *bundle;
@property (nonatomic, readonly, weak) id<InstallerProgressAppControllerDelegate> delegate;
@property (nonatomic, readonly) id<SUInstallerStatusProtocol> statusInfo;

@end

@implementation InstallerProgressAppController

@synthesize application = _application;
@synthesize bundle = _bundle;
@synthesize delegate = _delegate;
@synthesize statusInfo = _statusInfo;

- (instancetype)initWithApplication:(NSApplication *)application arguments:(NSArray<NSString *> *)arguments delegate:(id<InstallerProgressAppControllerDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        if (arguments.count != 2) {
            exit(EXIT_FAILURE);
        }
        
        NSString *hostBundlePath = arguments[1];
        NSBundle *bundle = [NSBundle bundleWithPath:hostBundlePath];
        if (bundle == nil) {
            SULog(@"Error: bundle at %@ is nil", hostBundlePath);
            exit(EXIT_FAILURE);
        }
        
        NSString *bundleIdentifier = bundle.bundleIdentifier;
        if (bundleIdentifier == nil) {
            SULog(@"Error: Bundle Identifier for target is nil");
            exit(EXIT_FAILURE);
        }
        
        application.applicationIconImage = [SUApplicationInfo bestIconForBundle:bundle];

        application.delegate = self;
        
        _application = application;
        _delegate = delegate;
        _bundle = bundle;
        _statusInfo = [[SUInstallerStatus alloc] init];
        
        [_statusInfo setInvalidationHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [application terminate:nil];
            });
        }];
        
        [_statusInfo setServiceName:SUStatusInfoServiceNameForBundleIdentifier(bundleIdentifier)];
    }
    return self;
}

- (void)run
{
    [self.application run];
}

- (void)applicationDidFinishLaunching:(NSNotification *)__unused notification
{
    [self.statusInfo probeStatusConnectivityWithReply:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate applicationDidFinishLaunchingWithTargetBundle:self.bundle];
        });
    }];
}

// Close status window immediately, but delay termination for a little bit to better increase the chance
// the updated application when relaunched will be the frontmost application
// This is related to macOS activation issues when terminating a frontmost application happens right before
// launching another app
- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)__unused sender
{
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(SUTerminationTimeDelay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // Exit right away, don't go through the apple event process again
        exit(EXIT_SUCCESS);
    });
    // Reply with a 'cancel' rather than 'later' because 'later' may make the runloop stop completely, not having the dispatch_after above invoked
    return NSTerminateCancel;
}

@end
