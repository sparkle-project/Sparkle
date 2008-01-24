//
//  NSBundle+SUAdditions.m
//  Sparkle
//
//  Created by Andy Matuschak on 12/21/07.
//  Copyright 2007 Andy Matuschak. All rights reserved.
//

#import "Sparkle.h"
#import "NSBundle+SUAdditions.h"

@implementation NSBundle (SUAdditions)

- (NSString *)name
{
	NSString *name = [self objectForInfoDictionaryKey:@"CFBundleDisplayName"];
	if (name)
		return name;
	else
		return [[[NSFileManager defaultManager] displayNameAtPath:[self bundlePath]] stringByDeletingPathExtension];
}

- (NSString *)version
{
	return [self objectForInfoDictionaryKey:@"CFBundleVersion"];
}

- (NSString *)displayVersion
{
	NSString *shortVersionString = [self objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	if (shortVersionString)
		return shortVersionString;
	else
		return [self version]; // Fall back on the normal version string.
}

- (NSImage *)icon
{
	// Cache the application icon.
	NSString *iconPath = [self pathForResource:[self objectForInfoDictionaryKey:@"CFBundleIconFile"] ofType:@"icns"];
	// According to the OS X docs, "CFBundleIconFile - This key identifies the file containing
	// the icon for the bundle. The filename you specify does not need to include the .icns
	// extension, although it may."
	//
	// However, if it *does* include the '.icns' the above method fails (tested on OS X 10.3.9) so we'll also try:
	if (!iconPath)
		iconPath = [self pathForResource:[self objectForInfoDictionaryKey:@"CFBundleIconFile"] ofType: nil];
	NSImage *icon = [[[NSImage alloc] initWithContentsOfFile:iconPath] autorelease];
	if (icon)
		return icon;	else // Use a default icon if none is defined.
	return [[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kGenericApplicationIcon)];
}

- (BOOL)isRunningFromDiskImage
{	
	return [[[NSWorkspace sharedWorkspace] propertiesForPath:[self bundlePath]] objectForKey:NSWorkspace_RBimagefilepath] != nil;
}

- (NSArray *)systemProfile
{
	return [[SUSystemProfiler sharedSystemProfiler] systemProfileArrayForHostBundle:self];
}

@end
