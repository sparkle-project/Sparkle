//
//  SUSparkleUserUpdaterDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/14/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUUserUpdaterDriver.h"

@class SUHost;

@protocol SUSparkleUserUpdaterDriverDelegate <NSObject>

@optional

- (BOOL)responsibleForInitiatingUpdateCheckForUserDriver:(id <SUUserUpdaterDriver>)userUpdaterDriver;
- (void)initiateUpdateCheckForUserDriver:(id <SUUserUpdaterDriver>)userUpdaterDriver;

- (void)userUpdaterDriverWillShowModalAlert:(id <SUUserUpdaterDriver>)userUpdaterDriver;
- (void)userUpdaterDriverDidShowModalAlert:(id <SUUserUpdaterDriver>)userUpdaterDriver;

@end

@interface SUSparkleUserUpdaterDriver : NSObject <SUUserUpdaterDriver>

- (instancetype)initWithHost:(SUHost *)host handlesTermination:(BOOL)handlesTermination delegate:(id <SUSparkleUserUpdaterDriverDelegate>)delegate;

@property (nonatomic, readonly, weak) id <SUSparkleUserUpdaterDriverDelegate> delegate;
@property (nonatomic, readonly, getter = isInstallingUpdateOnTermination) BOOL installingUpdateOnTermination;

- (void)sendTerminationSignalWithCompletion:(void (^)(void))finishTermination;

@end
