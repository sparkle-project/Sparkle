//
//  InstallerProgressAppController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 4/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "InstallerProgressAppController.h"
#import "InstallerProgressAppControllerDelegate.h"
#import "SURemoteMessagePort.h"
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
@property (nonatomic, readonly) SURemoteMessagePort *remotePort;

@end

@implementation InstallerProgressAppController

@synthesize application = _application;
@synthesize bundle = _bundle;
@synthesize delegate = _delegate;
@synthesize remotePort = _remotePort;

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
        _remotePort = [[SURemoteMessagePort alloc] initWithServiceName:SUAutoUpdateServiceNameForBundleIdentifier(bundleIdentifier)];
    }
    return self;
}

- (void)run
{
    [self.application run];
}

- (void)applicationDidFinishLaunching:(NSNotification *)__unused notification
{
    __weak InstallerProgressAppController *weakSelf = self;
    [self.remotePort connectWithLookupCompletion:^(BOOL success) {
        if (!success) {
            [NSApp terminate:nil];
        } else {
            [weakSelf.remotePort setInvalidationHandler:^{
                [weakSelf.application terminate:nil];
            }];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                InstallerProgressAppController *strongSelf = weakSelf;
                if (strongSelf != nil) {
                    [strongSelf.delegate applicationDidFinishLaunchingWithTargetBundle:strongSelf.bundle];
                }
            });
        }
    }];
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
    
    [self.delegate applicationWillTerminateAfterDelay];
    
    return NSTerminateLater;
}

@end
