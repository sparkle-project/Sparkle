//
//  NSBundle+SUAdditions.m
//  Sparkle
//
//  Created by Andy Matuschak on 12/21/07.
//  Copyright 2007 Andy Matuschak. All rights reserved.
//

#import "NSBundle+SUAdditions.h"
#import "NSWorkspace_RBAdditions.h"

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
	{
		if ([shortVersionString isEqualToString:[self version]])
			return shortVersionString;
		else
			return [shortVersionString stringByAppendingFormat:@" (%@)", [self version]];
	}
	else
		return [self version]; // Fall back on the normal version string.
}

- (NSImage *)icon
{
	// Cache the application icon.
	NSString *iconPath = [self pathForResource:[self objectForInfoDictionaryKey:@"CFBundleIconFile"] ofType:@"icns"];
	NSImage *icon = [[[NSImage alloc] initWithContentsOfFile:iconPath] autorelease];
	if (icon)
		return icon;
	else // Use a default icon if none is defined.
        return [[NSWorkspace sharedWorkspace] iconForFileType:NSFileTypeForHFSTypeCode(kGenericApplicationIcon)];
}

- (BOOL)isRunningFromDiskImage
{	
	return [[[NSWorkspace sharedWorkspace] propertiesForPath:[self bundlePath]] objectForKey:NSWorkspace_RBimagefilepath] != nil;
}

@end
