//
//  SUUpdaterController.m
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUpdaterController.h"
#import "SUUpdater.h"
#import "SUHost.h"
#import "SUSparkleUserDriver.h"
#import "SUConstants.h"
#import "SULog.h"

static NSString *const SUUpdaterDefaultsObservationContext = @"SUUpdaterDefaultsObservationContext";

@interface SUUpdaterController ()

@property (nonatomic) SUUpdater *updater;

@end

@implementation SUUpdaterController

@synthesize updater = _updater;

- (instancetype)init
{
    self = [super init];
    if (self != nil) {
        [self registerAsObserver];
        
        NSBundle *hostBundle = [NSBundle mainBundle];
        id <SUUserDriver> driver = [[SUSparkleUserDriver alloc] initWithHostBundle:hostBundle delegate:nil];
        self.updater = [[SUUpdater alloc] initWithHostBundle:hostBundle userDriver:driver delegate:nil];
    }
    return self;
}

- (void)dealloc
{
    [self unregisterAsObserver];
}

- (IBAction)checkForUpdates:(id)__unused sender
{
    [self.updater checkForUpdates];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(checkForUpdates:)) {
        return !self.updater.updateInProgress;
    }
    return YES;
}

- (void)registerAsObserver
{
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self forKeyPath:[@"values." stringByAppendingString:SUScheduledCheckIntervalKey] options:(NSKeyValueObservingOptions)0 context:(__bridge void *)(SUUpdaterDefaultsObservationContext)];
    
    [[NSUserDefaultsController sharedUserDefaultsController] addObserver:self forKeyPath:[@"values." stringByAppendingString:SUEnableAutomaticChecksKey] options:(NSKeyValueObservingOptions)0 context:(__bridge void *)(SUUpdaterDefaultsObservationContext)];
}

- (void)unregisterAsObserver
{
    @try {
        [[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self forKeyPath:[@"values." stringByAppendingString:SUScheduledCheckIntervalKey]];
        [[NSUserDefaultsController sharedUserDefaultsController] removeObserver:self forKeyPath:[@"values." stringByAppendingString:SUEnableAutomaticChecksKey]];
    } @catch (NSException *) {
        SULog(@"Error: [SUUpdaterController unregisterAsObserver] called, but wasn't registered as an observer.");
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if (context == (__bridge void *)(SUUpdaterDefaultsObservationContext)) {
        // Allow a small delay, because perhaps the user or developer wants to change both preferences. This allows the developer to interpret a zero check interval as a sign to disable automatic checking.
        // Or we may get this from the developer and from our own KVO observation, this will effectively coalesce them.
        [self.updater resetUpdateCycleAfterShortDelay];
    } else {
        if ([super respondsToSelector:@selector(observeValueForKeyPath:ofObject:change:context:)]) {
            [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        }
    }
}

@end
