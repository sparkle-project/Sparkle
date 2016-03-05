//
//  SUUserDriverUIComponent.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/4/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SUStatusCompletionResults.h"

@protocol SUStandardUserDriverDelegate;
@protocol SUUserDriver;

@interface SUUserDriverUIComponent : NSObject

- (instancetype)initWithUserDriver:(id<SUUserDriver>)userDriver delegate:(id<SUStandardUserDriverDelegate>)delegate;

@property (nonatomic, readonly, weak) id<SUStandardUserDriverDelegate> delegate;

- (void)registerApplicationTermination:(void (^)(SUApplicationTerminationStatus))applicationTerminationHandler;

- (void)cancelObservingApplicationTermination;

- (void)unregisterApplicationTermination;

- (NSApplicationTerminateReply)sendApplicationTerminationSignal;

- (void)terminateApplication;

- (void)registerSystemPowerOff:(void (^)(SUSystemPowerOffStatus))systemPowerOffHandler;

- (void)unregisterSystemPowerOff;

- (void)dismissUpdateInstallation;

- (void)invalidate;

@end
