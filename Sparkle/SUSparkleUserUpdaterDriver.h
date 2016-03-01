//
//  SUSparkleUserUpdaterDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/14/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SUUserUpdaterDriver.h"

@protocol SUSparkleUserUpdaterDriverDelegate <NSObject>

@optional

- (BOOL)responsibleForInitiatingUpdateCheckForUserDriver:(id <SUUserUpdaterDriver>)userUpdaterDriver;
- (void)initiateUpdateCheckForUserDriver:(id <SUUserUpdaterDriver>)userUpdaterDriver;

- (BOOL)responsibleForSignalingApplicationTerminationForUserDriver:(id <SUUserUpdaterDriver>)userUpdaterDriver;

- (void)userUpdaterDriverWillShowModalAlert:(id <SUUserUpdaterDriver>)userUpdaterDriver;
- (void)userUpdaterDriverDidShowModalAlert:(id <SUUserUpdaterDriver>)userUpdaterDriver;

@end

@interface SUSparkleUserUpdaterDriver : NSObject <SUUserUpdaterDriver>

- (instancetype)initWithHostBundle:(NSBundle *)hostBundle delegate:(id <SUSparkleUserUpdaterDriverDelegate>)delegate;

@property (nonatomic, readonly, weak) id <SUSparkleUserUpdaterDriverDelegate> delegate;

@property (nonatomic, readonly, getter=isUpdateInProgress) BOOL updateInProgress;

- (NSApplicationTerminateReply)sendApplicationTerminationSignal;

@end
