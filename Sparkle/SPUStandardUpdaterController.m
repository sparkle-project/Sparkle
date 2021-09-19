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

@interface SPUStandardUpdaterController () <NSMenuItemValidation>

@property (nonatomic) SPUUpdater *updater;
@property (nonatomic) id<SPUUserDriver> userDriver;

@end

@implementation SPUStandardUpdaterController

@synthesize updater = _updater;
@synthesize userDriver = _userDriver;
@synthesize updaterDelegate = _updaterDelegate;
@synthesize userDriverDelegate = _userDriverDelegate;

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
    SPUStandardUserDriver *userDriver = [[SPUStandardUserDriver alloc] initWithHostBundle:hostBundle delegate:self.userDriverDelegate];
    
    self.updater = [[SPUUpdater alloc] initWithHostBundle:hostBundle applicationBundle:hostBundle userDriver:userDriver delegate:self.updaterDelegate];
    self.userDriver = userDriver;
}

- (instancetype)initWithUpdaterDelegate:(nullable id<SPUUpdaterDelegate>)updaterDelegate userDriverDelegate:(nullable id<SPUStandardUserDriverDelegate>)userDriverDelegate
{
    return [self initWithStartingUpdater:YES updaterDelegate:updaterDelegate userDriverDelegate:userDriverDelegate];
}

- (instancetype)initWithStartingUpdater:(BOOL)startUpdater updaterDelegate:(nullable id<SPUUpdaterDelegate>)updaterDelegate userDriverDelegate:(nullable id<SPUStandardUserDriverDelegate>)userDriverDelegate
{
    if ((self = [super init])) {
        _updaterDelegate = updaterDelegate;
        _userDriverDelegate = userDriverDelegate;

        [self _initUpdater];
        
        if (startUpdater) {
            [self startUpdater];
        }
    }
    return self;
}

- (void)setUpdaterDelegate:(id<SPUUpdaterDelegate>)updaterDelegate
{
    if (self.updater != nil) {
        NSLog(@"Error: %@ - cannot set updater delegate %@ after the updater has been initialized. If you are instantiating %@ programmatically, please pass the updater delegate in its initializer. If you are instantiating %@ in a nib, please set the updater delegate by connecting its outlet.", NSStringFromSelector(_cmd), updaterDelegate, [self className], [self className]);
    } else {
        _updaterDelegate = updaterDelegate;
    }
}

- (void)setUserDriverDelegate:(id<SPUStandardUserDriverDelegate>)userDriverDelegate
{
    if (self.updater != nil) {
        NSLog(@"Error: %@ - cannot set user driver delegate %@ after the updater has been initialized. If you are instantiating %@ programmatically, please pass the user driver delegate in its initializer. If you are instantiating %@ in a nib, please set the user driver delegate by connecting its outlet.", NSStringFromSelector(_cmd), userDriverDelegate, [self className], [self className]);
    } else {
        _userDriverDelegate = userDriverDelegate;
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
