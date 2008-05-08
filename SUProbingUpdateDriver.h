//
//  SUProbingUpdateDriver.h
//  Sparkle
//
//  Created by Andy Matuschak on 5/7/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#ifndef SUPROBINGUPDATEDRIVER_H
#define SUPROBINGUPDATEDRIVER_H

#import <Cocoa/Cocoa.h>
#import "SUBasicUpdateDriver.h"

// This replaces the old SUStatusChecker.
@interface SUProbingUpdateDriver : SUBasicUpdateDriver { }
@end

@interface NSObject (SUProbeDriverDelegateProtocol)
- (void)didFindValidUpdate:(SUAppcastItem *)item toHostBundle:(NSBundle *)hb;
- (void)didNotFindUpdateToHostBundle:(NSBundle *)hb;
@end

#endif
