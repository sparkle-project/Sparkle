//
//  Sparkle.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

//
// Prefix header for all source files of the 'Sparkle' target in the 'Sparkle' project.
//
#ifndef SPARKLE_H
#define SPARKLE_H
#define SULocalizedString(key,comment) NSLocalizedStringFromTableInBundle(key, @"Sparkle", [NSBundle bundleForClass:[self class]], comment)

#ifdef __OBJC__
#import <Cocoa/Cocoa.h>
#import "SUConstants.h"
#endif

// Apple recommends using SystemVersion.plist instead of Gestalt() here, don't ask me why.
// This code *should* use NSSearchPathForDirectoriesInDomains(NSCoreServiceDirectory, NSSystemDomainMask, YES)
// but that returns /Library/CoreServices for some reason
// This returns a version string of the form X.Y.Z
#define SUSystemVersionString() [[NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"] objectForKey:@"ProductVersion"]

#import "SUUpdater.h"
#import "SUConstants.h"
#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUUpdateAlert.h"
#import "SUAutomaticUpdateAlert.h"
#import "SUStatusController.h"
#import "SUUnarchiver.h"
#import "SUStatusChecker.h"
#import "SUUserDefaults.h"
#import "SUVersionComparisonProtocol.h"
#import "SUStandardVersionComparator.h"

#import "NSFileManager+Authentication.h"
#import "NSFileManager+Verification.h"
#import "NSBundle+SUAdditions.h"

#else
/* Sparkle.h included more than once */
#endif

