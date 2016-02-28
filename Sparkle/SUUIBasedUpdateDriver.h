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
#import "SUUpdateAlert.h"

@class SUStatusController;

@interface SUUIBasedUpdateDriver : SUBasicUpdateDriver <SUUnarchiverDelegate>

- (instancetype)initWithUpdater:(SUUpdater *)updater host:(SUHost *)host;

@end

#endif
