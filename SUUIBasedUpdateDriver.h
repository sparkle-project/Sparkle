//
//  SUUIBasedUpdateDriver.h
//  Sparkle
//
//  Created by Andy Matuschak on 5/5/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUUIBASEDUPDATEDRIVER_H
#define SUUIBASEDUPDATEDRIVER_H

#import <Cocoa/Cocoa.h>
#import "SUBasicUpdateDriver.h"

@class SUStatusController, SUUpdateAlert;
@interface SUUIBasedUpdateDriver : SUBasicUpdateDriver {
	SUStatusController *statusController;
	SUUpdateAlert *updateAlert;
}

- (void)showModalAlert:(NSAlert *)alert;

@end

#endif
