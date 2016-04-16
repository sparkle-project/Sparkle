//
//  SUStandardUpdaterController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUStandardUpdaterController.h"
#import "SUUpdater.h"
#import "SUHost.h"
#import "SUStandardUserDriver.h"
#import "SUConstants.h"
#import "SULog.h"
#import "SUStandardUserDriver.h"

static NSString *const SUUpdaterDefaultsObservationContext = @"SUUpdaterDefaultsObservationContext";

@interface SUStandardUpdaterController ()

@property (nonatomic) SUUpdater *updater;
@property (nonatomic) id <SUStandardUserDriver> userDriver;
@property (nonatomic) BOOL initializedUpdater;

@end

@implementation SUStandardUpdaterController

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
    if (!self.initializedUpdater) {
        self.initializedUpdater = YES;
        
        NSBundle *hostBundle = [NSBundle mainBundle];
        id <SUUserDriver, SUStandardUserDriver> userDriver = [[SUStandardUserDriver alloc] initWithHostBundle:hostBundle delegate:self.userDriverDelegate];
        self.updater = [[SUUpdater alloc] initWithHostBundle:hostBundle userDriver:userDriver delegate:self.updaterDelegate];
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
        SULog(@"Fatal updater error (%ld): %@", updaterError.code, updaterError.localizedDescription);
        abort();
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
