//
//  Sparkle.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06. (Modified by CDHW on 23/12/07)
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

//
// Prefix header for all source files of the 'Sparkle' target in the 'Sparkle' project.
//

#ifndef SPARKLE_H
#define SPARKLE_H

#define SULocalizedString(key,comment) NSLocalizedStringFromTableInBundle(key, @"Sparkle", [NSBundle bundleForClass:[self class]], comment)
#define SUAbstractFail() NSAssert2(nil, @"Can't call %@ on an instance of %@; this is an abstract method!", __PRETTY_FUNCTION__, [self class]);

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#import "SUConstants.h"
#endif


// This list should include the shared headers. It doesn't matter if some of them aren't shared (unless
// there are name-space collisions) so we can list all of them to start with:

#import "NSBundle+SUAdditions.h"
#import "NSFileManager+Aliases.h"
#import "NSFileManager+Authentication.h"
#import "NSFileManager+Verification.h"
#import "NSWorkspace_RBAdditions.h"
#import "NSWorkspace+SystemVersion.h"

#import "NTSynchronousTask.h"

#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUAutomaticUpdateAlert.h"
#import "SUAutomaticUpdateDriver.h"
#import "SUBasicUpdateDriver.h"
#import "SUConstants.h"
#import "SUInstaller.h"
#import "SUProbingUpdateDriver.h"
#import "SUScheduledUpdateDriver.h"
#import "SUStandardVersionComparator.h"
#import "SUStatusController.h"
#import "SUSystemProfiler.h"
#import "SUUIBasedUpdateDriver.h"
#import "SUUnarchiver.h"
#import "SUUpdateAlert.h"
#import "SUUpdateDriver.h"
#import "SUUpdater.h"
#import "SUUpdatePermissionPrompt.h"
#import "SUUserInitiatedUpdateDriver.h"
#import "SUUserDefaults.h"
#import "SUVersionComparisonProtocol.h"
#import "SUWindowController.h"

#endif
