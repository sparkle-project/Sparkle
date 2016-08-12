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

@property (nonatomic, copy) void (^installUpdateHandler)(SUInstallUpdateStatus);
@property (nonatomic, copy) void (^updateCheckStatusCompletion)(SUUserInitiatedCheckStatus);
@property (nonatomic, copy) void (^downloadStatusCompletion)(SUDownloadUpdateStatus);
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

- (void)registerInstallUpdateHandler:(void (^)(SUInstallUpdateStatus))installUpdateHandler
{
    self.installUpdateHandler = installUpdateHandler;
}

- (void)installUpdateWithChoice:(SUInstallUpdateStatus)choice
{
    if (self.installUpdateHandler != nil) {
        self.installUpdateHandler(choice);
        self.installUpdateHandler = nil;
    }
}

- (void)dismissInstallAndRestart
{
    if (self.installUpdateHandler != nil) {
        self.installUpdateHandler(SUDismissUpdateInstallation);
        self.installUpdateHandler = nil;
    }
}

#pragma mark Update Check Status

- (void)registerUpdateCheckStatusHandler:(void (^)(SUUserInitiatedCheckStatus))updateCheckStatusCompletion
{
    self.updateCheckStatusCompletion = updateCheckStatusCompletion;
}

- (void)cancelUpdateCheckStatus
{
    if (self.updateCheckStatusCompletion != nil) {
        self.updateCheckStatusCompletion(SUUserInitiatedCheckCanceled);
        self.updateCheckStatusCompletion = nil;
    }
}

- (void)completeUpdateCheckStatus
{
    if (self.updateCheckStatusCompletion != nil) {
        self.updateCheckStatusCompletion(SUUserInitiatedCheckDone);
        self.updateCheckStatusCompletion = nil;
    }
}

#pragma mark Download Status

- (void)registerDownloadStatusHandler:(void (^)(SUDownloadUpdateStatus))downloadUpdateStatusCompletion
{
    self.downloadStatusCompletion = downloadUpdateStatusCompletion;
}

- (void)cancelDownloadStatus
{
    if (self.downloadStatusCompletion != nil) {
        self.downloadStatusCompletion(SUDownloadUpdateCanceled);
        self.downloadStatusCompletion = nil;
    }
}

- (void)completeDownloadStatus
{
    if (self.downloadStatusCompletion != nil) {
        self.downloadStatusCompletion(SUDownloadUpdateDone);
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
