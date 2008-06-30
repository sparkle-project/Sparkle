//
//  NSWorkspace+SystemVersion.m
//  Sparkle
//
//  Created by Andy Matuschak on 5/7/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "NSWorkspace+SystemVersion.h"


@implementation NSWorkspace (SUSystemVersion)
+ (NSString *)systemVersionString
{
	// This returns a version string of the form X.Y.Z
	// There may be a better way to deal with the problem that gestaltSystemVersionMajor
	//  et al. are not defined in 10.3, but this is probably good enough.
	NSString* verStr = nil;
#if MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_4
	SInt32 major, minor, bugfix;
	OSErr err1 = Gestalt(gestaltSystemVersionMajor, &major);
	OSErr err2 = Gestalt(gestaltSystemVersionMinor, &minor);
	OSErr err3 = Gestalt(gestaltSystemVersionBugFix, &bugfix);
	if (!err1 && !err2 && !err3)
	{
		verStr = [NSString stringWithFormat:@"%d.%d.%d", major, minor, bugfix];
	}
	else
#endif
	{
	 	NSString *versionPlistPath = @"/System/Library/CoreServices/SystemVersion.plist";
		verStr = [[[NSDictionary dictionaryWithContentsOfFile:versionPlistPath] objectForKey:@"ProductVersion"] retain];
	}
	return verStr;
}
@end
