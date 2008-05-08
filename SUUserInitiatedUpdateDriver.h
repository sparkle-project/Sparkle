//
//  SUUserInitiatedUpdateDriver.h
//  Sparkle
//
//  Created by Andy Matuschak on 5/5/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUUSERINITIATEDUPDATEDRIVER_H
#define SUUSERINITIATEDUPDATEDRIVER_H

#import <Cocoa/Cocoa.h>
#import "SUBasicUpdateDriver.h"

@class SUStatusController, SUUpdateAlert;
@interface SUUserInitiatedUpdateDriver : SUBasicUpdateDriver {
	SUStatusController *statusController;
	SUUpdateAlert *updateAlert;
}

@end

#endif
