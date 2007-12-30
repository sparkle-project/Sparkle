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

#import <CoreServices/CoreServices.h>
#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#import "SUConstants.h"
#endif

// This returns a version string of the form X.Y.Z
inline NSString* SUSystemVersionString(void)
{
	long major, minor, bugfix;
	OSErr err1 = Gestalt (gestaltSystemVersionMajor, &major);
	OSErr err2 = Gestalt (gestaltSystemVersionMinor, &minor);
	OSErr err3 = Gestalt (gestaltSystemVersionBugFix, &bugfix);
	NSString* verStr = nil;
	if (!err1 && !err2 && !err3)
	{
		verStr = [NSString stringWithFormat:@"%ld.%ld.%ld", major, minor, bugfix];
	}
	return verStr;
}


// This list should include the shared headers. It doesn't matter if some of them aren't shared (unless
// there are name-space collisions) so we can list all of them to start with:

#import "NSBundle+SUAdditions.h"
#import "NSFileManager+Authentication.h"
#import "NSFileManager+Verification.h"
#import "NSString+extras.h"
#import "NSWorkspace_RBAdditions.h"

#import "NTSynchronousTask.h"

#import "RSS.h"

#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUAutomaticUpdateAlert.h"
#import "SUConstants.h"
#import "SUStandardVersionComparator.h"
#import "SUStatusChecker.h"
#import "SUStatusController.h"
#import "SUSystemProfiler.h"
#import "SUUnarchiver.h"
#import "SUUpdateAlert.h"
#import "SUUpdater.h"
#import "SUUserDefaults.h"
#import "SUVersionComparisonProtocol.h"

#endif
