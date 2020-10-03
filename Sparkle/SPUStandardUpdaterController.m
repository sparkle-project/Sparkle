//
//  SPUStandardUpdaterController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUStandardUpdaterController.h"
#import "SPUUpdater.h"
#import "SUHost.h"
#import "SPUStandardUserDriver.h"
#import "SUConstants.h"
#import "SULog.h"

static NSString *const SUUpdaterDefaultsObservationContext = @"SUUpdaterDefaultsObservationContext";

@interface SPUStandardUpdaterController ()

@property (nonatomic) SPUUpdater *updater;
@property (nonatomic) id <SPUStandardUserDriverProtocol> userDriver;
@property (nonatomic) BOOL initializedUpdater;

@end

@implementation SPUStandardUpdaterController

@synthesize updater = _updater;
@synthesize userDriver = _userDriver;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize userDriverDelegate = _userDriverDelegate;
@synthesize initializedUpdater = _initializedUpdater;

- (void)awakeFromNib
{
    // awakeFromNib might be called more than once; guard against that
    // We have to use awakeFromNib otherwise the delegate outlets may not be connected yet,
    // and we aren't a proper window or view controller, so we don't have a proper "did load" point
    [self initializeUpdater];
}

- (instancetype)initWithUpdaterDelegate:(nullable id<SPUUpdaterDelegate>)updaterDelegate userDriverDelegate:(nullable id<SPUStandardUserDriverDelegate>)userDriverDelegate
{
    if ((self = [super init])) {
        _updaterDelegate = updaterDelegate;
        _userDriverDelegate = userDriverDelegate;

        [self initializeUpdater];
    }
    return self;
}

- (void)initializeUpdater
{
    if (!self.initializedUpdater) {
        self.initializedUpdater = YES;
        
        NSBundle *hostBundle = [NSBundle mainBundle];
        id <SPUUserDriver, SPUStandardUserDriverProtocol> userDriver = [[SPUStandardUserDriver alloc] initWithHostBundle:hostBundle delegate:self.userDriverDelegate];
        self.updater = [[SPUUpdater alloc] initWithHostBundle:hostBundle applicationBundle:hostBundle userDriver:userDriver delegate:self.updaterDelegate];
        self.userDriver = userDriver;
        
        // In the case this is being called right as an application is being launched,
        // the application may not have finished launching - we shouldn't do anything before the main runloop is started
        // Note we can't say, register for an application did finish launching notification
        // because we can't assume when our framework or this class will be loaded/instantiated before that
        [self performSelector:@selector(startUpdater) withObject:nil afterDelay:0];
    }
}

- (void)startUpdater
{
    NSError *updaterError = nil;
    if (![self.updater startUpdater:&updaterError]) {
        SULog(SULogLevelError, @"Fatal updater error (%ld): %@", updaterError.code, updaterError.localizedDescription);
        
        // Delay the alert four seconds so it doesn't show RIGHT as the app launches, but also doesn't interrupt the user once they really get to work.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Unable to Check For Updates";
            alert.informativeText = @"The update checker failed to start correctly. You should contact the app developer to report this issue and verify that you have the latest version.";
            [alert addButtonWithTitle:@"OK"];
            [alert runModal];
        });
    }
}

- (IBAction)checkForUpdates:(id)__unused sender
{
    [self.updater checkForUpdates];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(checkForUpdates:)) {
        return self.userDriver.canCheckForUpdates;
    }
    return YES;
}

@end
