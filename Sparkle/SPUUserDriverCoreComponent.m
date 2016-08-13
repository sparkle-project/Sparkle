//
//  SUUserDriverCoreComponent.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/4/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUUserDriverCoreComponent.h"
#import "SPUStandardUserDriverDelegate.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SPUUserDriverCoreComponent ()

@property (nonatomic) BOOL canCheckForUpdates;

@property (nonatomic, copy) void (^installUpdateHandler)(SPUInstallUpdateStatus);
@property (nonatomic, copy) void (^updateCheckStatusCompletion)(SPUUserInitiatedCheckStatus);
@property (nonatomic, copy) void (^downloadStatusCompletion)(SPUDownloadUpdateStatus);
@property (nonatomic, copy) void (^acknowledgement)(void);

@end

@implementation SPUUserDriverCoreComponent

@synthesize delegate = _delegate;
@synthesize canCheckForUpdates = _canCheckForUpdates;
@synthesize installUpdateHandler = _installUpdateHandler;
@synthesize updateCheckStatusCompletion = _updateCheckStatusCompletion;
@synthesize downloadStatusCompletion = _downloadStatusCompletion;
@synthesize acknowledgement = _acknowledgement;

#pragma mark Birth

- (instancetype)initWithDelegate:(id<SPUStandardUserDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

#pragma mark Is Update Busy?

- (void)showCanCheckForUpdates:(BOOL)canCheckForUpdates
{
    self.canCheckForUpdates = canCheckForUpdates;
}

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

#pragma mark Update Check Status

- (void)registerUpdateCheckStatusHandler:(void (^)(SPUUserInitiatedCheckStatus))updateCheckStatusCompletion
{
    self.updateCheckStatusCompletion = updateCheckStatusCompletion;
}

- (void)cancelUpdateCheckStatus
{
    if (self.updateCheckStatusCompletion != nil) {
        self.updateCheckStatusCompletion(SPUUserInitiatedCheckCanceled);
        self.updateCheckStatusCompletion = nil;
    }
}

- (void)completeUpdateCheckStatus
{
    if (self.updateCheckStatusCompletion != nil) {
        self.updateCheckStatusCompletion(SPUUserInitiatedCheckDone);
        self.updateCheckStatusCompletion = nil;
    }
}

#pragma mark Download Status

- (void)registerDownloadStatusHandler:(void (^)(SPUDownloadUpdateStatus))downloadUpdateStatusCompletion
{
    self.downloadStatusCompletion = downloadUpdateStatusCompletion;
}

- (void)cancelDownloadStatus
{
    if (self.downloadStatusCompletion != nil) {
        self.downloadStatusCompletion(SPUDownloadUpdateCanceled);
        self.downloadStatusCompletion = nil;
    }
}

- (void)completeDownloadStatus
{
    if (self.downloadStatusCompletion != nil) {
        self.downloadStatusCompletion(SPUDownloadUpdateDone);
        self.downloadStatusCompletion = nil;
    }
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
    [self acceptAcknowledgement];
    [self cancelUpdateCheckStatus];
    [self cancelDownloadStatus];
    [self dismissInstallAndRestart];
}

@end
