//
//  SPUUserDriverUIComponent.h
//  Sparkle
//
//  Created by Mayur Pawashe on 8/13/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUExport.h"

NS_ASSUME_NONNULL_BEGIN

SU_EXPORT @interface SPUUserDriverUIComponent : NSObject

- (instancetype)init;

- (BOOL)terminateApplicationForBundleAndWillTerminateCurrentApplication:(NSBundle *)bundle;

- (void)terminateApplicationForBundle:(NSBundle *)bundle;

- (BOOL)applicationIsAliveForBundle:(NSBundle *)bundle;

@end

NS_ASSUME_NONNULL_END
