//
//  SUUserDriverCoreComponent.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/4/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUStatusCompletionResults.h"
#import "SUExport.h"

@protocol SUStandardUserDriverDelegate;

SU_EXPORT @interface SUUserDriverCoreComponent : NSObject

- (instancetype)initWithDelegate:(id<SUStandardUserDriverDelegate>)delegate;

@property (nonatomic, readonly, weak) id<SUStandardUserDriverDelegate> delegate;

- (void)idleOnUpdateChecks:(BOOL)shouldIdleOnUpdateChecks;

@property (nonatomic, readonly) BOOL idlesOnUpdateChecks;

- (void)showUpdateInProgress:(BOOL)isUpdateInProgress;

@property (nonatomic, readonly, getter=isUpdateInProgress) BOOL updateInProgress;

@property (nonatomic, readonly) BOOL willInitiateNextUpdateCheck;

- (void)startUpdateCheckTimerWithNextTimeInterval:(NSTimeInterval)timeInterval reply:(void (^)(SUUpdateCheckTimerStatus))reply;
- (void)invalidateUpdateCheckTimer;

- (void)registerInstallUpdateHandler:(void (^)(SUInstallUpdateStatus))installUpdateHandler;
- (void)installAndRestart;

- (void)registerUpdateCheckStatusHandler:(void (^)(SUUserInitiatedCheckStatus))updateCheckStatusCompletion;
- (void)cancelUpdateCheckStatus;
- (void)completeUpdateCheckStatus;

- (void)registerDownloadStatusHandler:(void (^)(SUDownloadUpdateStatus))downloadUpdateStatusCompletion;
- (void)cancelDownloadStatus;
- (void)completeDownloadStatus;

- (void)registerAcknowledgement:(void (^)(void))acknowledgement;
- (void)acceptAcknowledgement;

- (void)dismissUpdateInstallation;

- (void)invalidate;

@end
