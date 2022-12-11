//
//  SPUProbingUpdateDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SPUUpdateDriver.h"

NS_ASSUME_NONNULL_BEGIN

@class SUHost;
@protocol SPUUpdaterDelegate;

@interface SPUProbingUpdateDriver : NSObject <SPUUpdateDriver>

- (instancetype)initWithHost:(SUHost *)host updater:(id)updater updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate __attribute__((objc_direct));

@end

NS_ASSUME_NONNULL_END
