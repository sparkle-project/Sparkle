//
//  SUUserUpdaterDriverDelegate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/29/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol SUUserUpdaterDriver;

@protocol SUUserUpdaterDriverDelegate <NSObject>

@optional

- (BOOL)responsibleForInitiatingUpdateCheckForUserDriver:(id <SUUserUpdaterDriver>)userUpdaterDriver;
- (void)initiateUpdateCheckForUserDriver:(id <SUUserUpdaterDriver>)userUpdaterDriver;

- (BOOL)responsibleForSignalingApplicationTerminationForUserDriver:(id <SUUserUpdaterDriver>)userUpdaterDriver;

- (void)userUpdaterDriverWillShowModalAlert:(id <SUUserUpdaterDriver>)userUpdaterDriver;
- (void)userUpdaterDriverDidShowModalAlert:(id <SUUserUpdaterDriver>)userUpdaterDriver;

@end
