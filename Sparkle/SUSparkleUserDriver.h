//
//  SUSparkleUserDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/14/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "SUUserDriver.h"

NS_ASSUME_NONNULL_BEGIN

@protocol SUVersionDisplay;

@protocol SUSparkleUserDriverDelegate <NSObject>

@optional

- (BOOL)responsibleForInitiatingUpdateCheckForUserDriver:(id <SUUserDriver>)userDriver;
- (void)initiateUpdateCheckForUserDriver:(id <SUUserDriver>)userDriver;

- (BOOL)responsibleForSignalingApplicationTerminationForUserDriver:(id <SUUserDriver>)userDriver;

- (void)userUpdaterDriverWillShowModalAlert:(id <SUUserDriver>)userDriver;
- (void)userUpdaterDriverDidShowModalAlert:(id <SUUserDriver>)userDriver;

- (_Nullable id <SUVersionDisplay>)versionDisplayerForUserDriver:(id <SUUserDriver>)userDriver;

@end

@interface SUSparkleUserDriver : NSObject <SUUserDriver>

- (instancetype)initWithHostBundle:(NSBundle *)hostBundle delegate:(_Nullable id <SUSparkleUserDriverDelegate>)delegate;

@property (nonatomic, readonly, weak, nullable) id <SUSparkleUserDriverDelegate> delegate;

@property (nonatomic, readonly, getter=isUpdateInProgress) BOOL updateInProgress;

- (NSApplicationTerminateReply)sendApplicationTerminationSignal;

@end

NS_ASSUME_NONNULL_END
