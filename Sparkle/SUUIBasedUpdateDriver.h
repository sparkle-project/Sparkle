//
//  SUUIBasedUpdateDriver.h
//  Sparkle
//
//  Created by Andy Matuschak on 5/5/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUUIBASEDUPDATEDRIVER_H
#define SUUIBASEDUPDATEDRIVER_H

#import <Foundation/Foundation.h>
#import "SUBasicUpdateDriver.h"

@class SUStatusController;

@interface SUUIBasedUpdateDriver : SUBasicUpdateDriver

- (instancetype)initWithUpdater:(id)updater updaterDelegate:(id<SUUpdaterDelegate>)updaterDelegate userDriver:(id<SUUserDriver>)userDriver host:(SUHost *)host sparkleBundle:(NSBundle *)sparkleBundle;

@end

#endif
