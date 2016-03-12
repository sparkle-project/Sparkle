//
//  SUUserDriverUIComponent.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/4/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUserDriverUIComponent.h"
#import "SUStandardUserDriverDelegate.h"
#import "SUStandardUserDriverRemoteDelegate.h"

@interface SUUserDriverUIComponent ()

@property (nonatomic) BOOL installingUpdateOnTermination;
@property (nonatomic) BOOL askedHandlingTermination;
@property (nonatomic, readonly) BOOL handlesTermination;

@property (nonatomic, copy) void (^applicationTerminationHandler)(SUApplicationTerminationStatus);
@property (nonatomic, copy) void (^systemPowerOffHandler)(SUSystemPowerOffStatus);

@end

@implementation SUUserDriverUIComponent

@synthesize delegate = _delegate;
@synthesize installingUpdateOnTermination = _installingUpdateOnTermination;
@synthesize askedHandlingTermination = _askedHandlingTermination;
@synthesize handlesTermination = _handlesTermination;
@synthesize applicationTerminationHandler = _applicationTerminationHandler;
@synthesize systemPowerOffHandler = _systemPowerOffHandler;

#pragma mark Birth

- (instancetype)initWithDelegate:(id<SUStandardUserDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

#pragma mark Application Death

- (BOOL)handlesTermination
{
    if (!self.askedHandlingTermination) {
        if ([self.delegate respondsToSelector:@selector(responsibleForSignalingApplicationTermination)]) {
            _handlesTermination = ![self.delegate responsibleForSignalingApplicationTermination];
        } else {
            _handlesTermination = YES;
        }
        self.askedHandlingTermination = YES;
    }
    return _handlesTermination;
}

- (void)registerApplicationTermination:(void (^)(SUApplicationTerminationStatus))applicationTerminationHandler
{
    self.installingUpdateOnTermination = YES;
    
    // Sudden termination is available on 10.6+
    [[NSProcessInfo processInfo] disableSuddenTermination];
    
    self.applicationTerminationHandler = applicationTerminationHandler;
    
    if (self.handlesTermination) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationWillTerminate:) name:NSApplicationWillTerminateNotification object:nil];
    }
}

- (void)cancelObservingApplicationTermination
{
    if (self.installingUpdateOnTermination) {
        [[NSProcessInfo processInfo] enableSuddenTermination];
        
        if (self.handlesTermination) {
            [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationWillTerminateNotification object:nil];
        }
        
        if (self.applicationTerminationHandler != nil) {
            self.applicationTerminationHandler(SUApplicationStoppedObservingTermination);
            self.applicationTerminationHandler = nil;
        }
        
        self.installingUpdateOnTermination = NO;
    }
}

- (void)unregisterApplicationTermination
{
    [self cancelObservingApplicationTermination];
}

- (void)applicationWillTerminate:(NSNotification *)__unused note
{
    [self sendApplicationTerminationSignal];
}

- (NSApplicationTerminateReply)sendApplicationTerminationSignal
{
    if (self.installingUpdateOnTermination) {
        if (self.applicationTerminationHandler != nil) {
            self.applicationTerminationHandler(SUApplicationWillTerminate);
            self.applicationTerminationHandler = nil;
        }
        
        return NSTerminateLater;
    }
    
    return NSTerminateNow;
}

- (void)terminateApplication
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.installingUpdateOnTermination && !self.handlesTermination) {
            [NSApp replyToApplicationShouldTerminate:YES];
        } else {
            [NSApp terminate:nil];
        }
    });
}

#pragma mark System Death

- (void)registerSystemPowerOff:(void (^)(SUSystemPowerOffStatus))systemPowerOffHandler
{
    self.systemPowerOffHandler = systemPowerOffHandler;
    
    [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self selector:@selector(systemWillPowerOff:) name:NSWorkspaceWillPowerOffNotification object:nil];
}

- (void)cancelObservingSystemPowerOff
{
    if (self.systemPowerOffHandler != nil) {
        self.systemPowerOffHandler(SUStoppedObservingSystemPowerOff);
        self.systemPowerOffHandler = nil;
        
        [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self name:NSWorkspaceWillPowerOffNotification object:nil];
    }
}

- (void)unregisterSystemPowerOff
{
    [self cancelObservingSystemPowerOff];
}

- (void)systemWillPowerOff:(NSNotification *)__unused notification
{
    if (self.systemPowerOffHandler != nil) {
        self.systemPowerOffHandler(SUSystemWillPowerOff);
        self.systemPowerOffHandler = nil;
    }
}

#pragma mark Aborting Everything

- (void)dismissUpdateInstallation
{
    [self cancelObservingApplicationTermination];
    [self cancelObservingSystemPowerOff];
}

- (void)invalidate
{
    // Make sure any remote handlers will not be invoked
    self.applicationTerminationHandler = nil;
    self.systemPowerOffHandler = nil;
    
    // Dismiss the installation normally
    [self dismissUpdateInstallation];
}

@end
