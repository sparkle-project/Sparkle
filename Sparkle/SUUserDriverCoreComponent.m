//
//  SUUserDriverCoreComponent.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/4/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SUUserDriverCoreComponent.h"
#import "SUStandardUserDriverDelegate.h"
#import "SUStandardUserDriverRemoteDelegate.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUUserDriverCoreComponent ()

@property (nonatomic) BOOL idlesOnUpdateChecks;
@property (nonatomic) BOOL updateInProgress;

@property (nonatomic) NSTimer *checkUpdateTimer;
@property (nonatomic, copy) void (^checkForUpdatesReply)(SUUpdateCheckTimerStatus);

@property (nonatomic, copy) void (^installUpdateHandler)(SUInstallUpdateStatus);
@property (nonatomic, copy) void (^updateCheckStatusCompletion)(SUUserInitiatedCheckStatus);
@property (nonatomic, copy) void (^downloadStatusCompletion)(SUDownloadUpdateStatus);
@property (nonatomic, copy) void (^acknowledgement)(void);

@end

@implementation SUUserDriverCoreComponent

@synthesize delegate = _delegate;
@synthesize idlesOnUpdateChecks = _idlesOnUpdateChecks;
@synthesize updateInProgress = _updateInProgress;
@synthesize checkUpdateTimer = _checkUpdateTimer;
@synthesize checkForUpdatesReply = _checkForUpdatesReply;
@synthesize installUpdateHandler = _installUpdateHandler;
@synthesize updateCheckStatusCompletion = _updateCheckStatusCompletion;
@synthesize downloadStatusCompletion = _downloadStatusCompletion;
@synthesize acknowledgement = _acknowledgement;

#pragma mark Birth

- (instancetype)initWithDelegate:(id<SUStandardUserDriverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _delegate = delegate;
    }
    return self;
}

#pragma mark Is Update Busy?

- (void)idleOnUpdateChecks:(BOOL)shouldIdleOnUpdateChecks
{
    self.idlesOnUpdateChecks = shouldIdleOnUpdateChecks;
}

- (void)showUpdateInProgress:(BOOL)isUpdateInProgress
{
    self.updateInProgress = isUpdateInProgress;
}

#pragma mark Check Updates Timer

- (BOOL)isDelegateResponsibleForUpdateChecking
{
    BOOL result = NO;
    if ([self.delegate respondsToSelector:@selector(responsibleForInitiatingUpdateCheck)]) {
        result = [self.delegate responsibleForInitiatingUpdateCheck];
    }
    return result;
}

- (BOOL)willInitiateNextUpdateCheck
{
    return (self.checkUpdateTimer != nil);
}

- (void)checkForUpdates:(NSTimer *)__unused timer
{
    if ([self isDelegateResponsibleForUpdateChecking]) {
        if ([self.delegate respondsToSelector:@selector(initiateUpdateCheck)]) {
            [self.delegate initiateUpdateCheck];
        } else {
            NSLog(@"Error: Delegate %@ for user driver %@ must implement initiateUpdateCheck because it returned YES from responsibleForInitiatingUpdateCheck", self.delegate, self);
        }
    } else {
        if (self.checkForUpdatesReply != nil) {
            self.checkForUpdatesReply(SUCheckForUpdateNow);
            self.checkForUpdatesReply = nil;
        }
    }
    
    [self invalidateUpdateCheckTimer];
}

- (void)startUpdateCheckTimerWithNextTimeInterval:(NSTimeInterval)timeInterval reply:(void (^)(SUUpdateCheckTimerStatus))reply
{
    if ([self isDelegateResponsibleForUpdateChecking]) {
        reply(SUCheckForUpdateWillOccurLater);
    } else {
        self.checkForUpdatesReply = reply;
    }
    
    self.checkUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:timeInterval target:self selector:@selector(checkForUpdates:) userInfo:nil repeats:NO];
}

- (void)invalidateUpdateCheckTimer
{
    if (self.checkUpdateTimer != nil) {
        [self.checkUpdateTimer invalidate];
        self.checkUpdateTimer = nil;
        
        if (self.checkForUpdatesReply != nil) {
            self.checkForUpdatesReply(SUCheckForUpdateWillOccurLater);
            self.checkForUpdatesReply = nil;
        }
    }
}

#pragma mark Install Updates

- (void)registerInstallUpdateHandler:(void (^)(SUInstallUpdateStatus))installUpdateHandler
{
    self.installUpdateHandler = installUpdateHandler;
}

- (void)installAndRestart
{
    if (self.installUpdateHandler != nil) {
        self.installUpdateHandler(SUInstallAndRelaunchUpdateNow);
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
        self.updateCheckStatusCompletion(SUUserInitiatedCheckCancelled);
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
        self.downloadStatusCompletion(SUDownloadUpdateCancelled);
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
    // Note: self.idlesOnUpdateChecks is intentionally not touched in case this instance is re-used
    
    self.updateInProgress = NO;
    
    [self acceptAcknowledgement];
    [self cancelUpdateCheckStatus];
    [self cancelDownloadStatus];
    [self dismissInstallAndRestart];
    
    // We don't invalidate the update check timer here because that's not really a part of the installation
    // and we might want to keep it still alive
}

- (void)invalidate
{
    // Make sure any remote handlers will not be invoked
    self.acknowledgement = nil;
    self.checkForUpdatesReply = nil;
    self.downloadStatusCompletion = nil;
    self.installUpdateHandler = nil;
    self.updateCheckStatusCompletion = nil;
    
    [self invalidateUpdateCheckTimer];
    
    // Dismiss the installation normally
    [self dismissUpdateInstallation];
}

@end
