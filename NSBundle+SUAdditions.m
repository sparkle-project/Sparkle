//
//  NSBundle+SUAdditions.m
//  Sparkle
//
//  Created by Andy Matuschak on 12/21/07.
//  Copyright 2007 Andy Matuschak. All rights reserved.
//

#import "Sparkle.h"
#import "NSBundle+SUAdditions.h"

#ifndef NSAppKitVersionNumber10_4
#define NSAppKitVersionNumber10_4 824
#endif

@implementation NSBundle (SUAdditions)

- (NSString *)name
{
	NSString *name = [self objectForInfoDictionaryKey:@"CFBundleDisplayName"];
	if (name) return name;
	
	name = [self objectForInfoDictionaryKey:@"CFBundleName"];
	if (name) return name;
	
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
	// Use a default icon if none is defined.
	if (!icon) { icon = [NSImage imageNamed:@"NSDefaultApplicationIcon"]; }
	return icon;
}

- (BOOL)isRunningFromDiskImage
{	
	// This check causes crashes on 10.3; for now, we'll just skip it.
	if (floor(NSAppKitVersionNumber) < NSAppKitVersionNumber10_4)
		return NO;
	
	NSDictionary *pathProperties = [[NSWorkspace sharedWorkspace] propertiesForPath:[self bundlePath]];
	BOOL isDiskImage = [pathProperties objectForKey:NSWorkspace_RBimagefilepath] != nil;
	BOOL isFileVault = [[pathProperties objectForKey:NSWorkspace_RBmntonname] hasPrefix:@"/Users/"];
	return isDiskImage && !isFileVault;
}

- (NSString *)publicDSAKey
{
	// Maybe the key is just a string in the Info.plist.
	NSString *key = [self objectForInfoDictionaryKey:SUPublicDSAKeyKey];
	if (key) { return key; }
	
	// More likely, we've got a reference to a Resources file by filename:
	NSString *keyFilename = [self objectForInfoDictionaryKey:SUPublicDSAKeyFileKey];
	if (!keyFilename) { return nil; }
	return [NSString stringWithContentsOfFile:[self pathForResource:keyFilename ofType:nil]];
}

- (NSArray *)systemProfile
{
	return [[SUSystemProfiler sharedSystemProfiler] systemProfileArrayForHostBundle:self];
}

@end
