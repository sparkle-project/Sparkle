//
//  SUProbingUpdateDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUUpdateDriver.h"

NS_ASSUME_NONNULL_BEGIN

@class SUHost;
@protocol SPUUpdaterDelegate;

@interface SUProbingUpdateDriver : NSObject <SUUpdateDriver>

- (instancetype)initWithHost:(SUHost *)host updater:(id)updater updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate;

@end

NS_ASSUME_NONNULL_END
