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

@interface SUSparkleUserUpdaterDriver : NSObject <SUUserUpdaterDriver>

- (instancetype)initWithHost:(SUHost *)host;

@end
