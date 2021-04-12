//
//  SUUserDriverCoreComponent.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/4/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUserDriverCoreComponent.h"


#include "AppKitPrevention.h"

@interface SPUUserDriverCoreComponent ()

@property (nonatomic, copy) void (^installUpdateHandler)(SPUInstallUpdateStatus);
@property (nonatomic, copy) void (^cancellation)(void);
@property (nonatomic, copy) void (^acknowledgement)(void);

@end

@implementation SPUUserDriverCoreComponent

@synthesize installUpdateHandler = _installUpdateHandler;
@synthesize cancellation = _cancellation;
@synthesize acknowledgement = _acknowledgement;

#pragma mark Install Updates

- (void)registerInstallUpdateHandler:(void (^)(SPUInstallUpdateStatus))installUpdateHandler
{
    self.installUpdateHandler = installUpdateHandler;
}

- (void)installUpdateWithChoice:(SPUInstallUpdateStatus)choice
{
    if (self.installUpdateHandler != nil) {
        self.installUpdateHandler(choice);
        self.installUpdateHandler = nil;
    }
}

- (void)dismissInstallAndRestart
{
    if (self.installUpdateHandler != nil) {
        self.installUpdateHandler(SPUDismissUpdateInstallation);
        self.installUpdateHandler = nil;
    }
}

#pragma mark Cancellation

- (void)registerCancellation:(void (^)(void))cancellation
{
    self.cancellation = cancellation;
}

- (void)cancel
{
    if (self.cancellation != nil) {
        self.cancellation();
        self.cancellation = nil;
    }
}

- (void)clearCancellation
{
    self.cancellation = nil;
}

#pragma mark Simple Acknoledgments

- (void)registerAcknowledgement:(void (^)(void))acknowledgement
{
    self.acknowledgement = acknowledgement;
}

- (void)acceptAcknowledgement
{
    if (self.acknowledgement != nil) {
        self.acknowledgement();
        self.acknowledgement = nil;
    }
}

#pragma mark Aborting Everything

- (void)dismissUpdateInstallation
{
    self.acknowledgement = nil;
    self.cancellation = nil;
    self.installUpdateHandler = nil;
}

@end
