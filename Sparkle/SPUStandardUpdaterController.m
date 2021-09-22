//
//  SPUStandardUpdaterController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import "SPUStandardUpdaterController.h"
#import "SPUUpdater.h"
#import "SUHost.h"
#import "SPUStandardUserDriver.h"
#import "SUConstants.h"
#import "SULog.h"
#import "SULocalizations.h"
#import <AppKit/AppKit.h>

// We use public instance variables instead of properties for the updater / user driver delegates
// because we want them to be connectable outlets from Interface Builder, but we do not want their setters to be invoked
// programmatically.

@interface SPUStandardUpdaterController () <NSMenuItemValidation>

@property (nonatomic) SPUUpdater *updater;
@property (nonatomic) id<SPUUserDriver> userDriver;

@end

@implementation SPUStandardUpdaterController

@synthesize updater = _updater;
@synthesize userDriver = _userDriver;

- (void)awakeFromNib
{
    // Note: awakeFromNib might be called more than once
    // We have to use awakeFromNib otherwise the delegate outlets may not be connected yet,
    // and we aren't a proper window or view controller, so we don't have a proper "did load" point
    if (self.updater == nil) {
        [self _initUpdater];
        [self startUpdater];
    }
}

- (void)_initUpdater
{
    NSBundle *hostBundle = [NSBundle mainBundle];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdirect-ivar-access"
    SPUStandardUserDriver *userDriver = [[SPUStandardUserDriver alloc] initWithHostBundle:hostBundle delegate:self->userDriverDelegate];
    
    self.updater = [[SPUUpdater alloc] initWithHostBundle:hostBundle applicationBundle:hostBundle userDriver:userDriver delegate:self->updaterDelegate];
    self.userDriver = userDriver;
#pragma clang diagnostic pop
}

- (instancetype)initWithUpdaterDelegate:(nullable id<SPUUpdaterDelegate>)theUpdaterDelegate userDriverDelegate:(nullable id<SPUStandardUserDriverDelegate>)theUserDriverDelegate
{
    return [self initWithStartingUpdater:YES updaterDelegate:theUpdaterDelegate userDriverDelegate:theUserDriverDelegate];
}

- (instancetype)initWithStartingUpdater:(BOOL)startUpdater updaterDelegate:(nullable id<SPUUpdaterDelegate>)theUpdaterDelegate userDriverDelegate:(nullable id<SPUStandardUserDriverDelegate>)theUserDriverDelegate
{
    if ((self = [super init])) {
        self->updaterDelegate = theUpdaterDelegate;
        self->userDriverDelegate = theUserDriverDelegate;

        [self _initUpdater];
        
        if (startUpdater) {
            [self startUpdater];
        }
    }
    return self;
}

- (void)startUpdater
{
    NSError *updaterError = nil;
    if (![self.updater startUpdater:&updaterError]) {
        SULog(SULogLevelError, @"Fatal updater error (%ld): %@", updaterError.code, updaterError.localizedDescription);
        
        // Delay the alert four seconds so it doesn't show RIGHT as the app launches, but also doesn't interrupt the user once they really get to work.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = SULocalizedString(@"Unable to Check For Updates", nil);
            alert.informativeText = SULocalizedString(@"The update checker failed to start correctly. You should contact the app developer to report this issue and verify that you have the latest version.", nil);
            [alert runModal];
        });
    }
}

- (IBAction)checkForUpdates:(nullable id)__unused sender
{
    [self.updater checkForUpdates];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(checkForUpdates:)) {
        return self.updater.canCheckForUpdates;
    }
    return YES;
}

@end

#endif
