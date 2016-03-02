//
//  SUSparkleUserDriverDelegate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/1/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SUUserDriver, SUVersionDisplay;

@protocol SUSparkleUserDriverDelegate <NSObject>

- (void)userDriverWillShowModalAlert:(id <SUUserDriver>)userDriver;
- (void)userDriverDidShowModalAlert:(id <SUUserDriver>)userDriver;

- (_Nullable id <SUVersionDisplay>)versionDisplayerForUserDriver:(id <SUUserDriver>)userDriver;

- (BOOL)responsibleForInitiatingUpdateCheckForUserDriver:(id <SUUserDriver>)userDriver;
- (void)initiateUpdateCheckForUserDriver:(id <SUUserDriver>)userDriver;

- (BOOL)responsibleForSignalingApplicationTerminationForUserDriver:(id <SUUserDriver>)userDriver;

@end

NS_ASSUME_NONNULL_END
