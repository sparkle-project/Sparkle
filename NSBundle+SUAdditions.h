//
//  NSBundle+SUAdditions.h
//  Sparkle
//
//  Created by Andy Matuschak on 12/21/07.
//  Copyright 2007 Andy Matuschak. All rights reserved.
//

#ifndef NSBUNDLE_PLUS_ADDITIONS_H
#define NSBUNDLE_PLUS_ADDITIONS_H

@interface NSBundle (SUAdditions)
/*!
	@method     
	@abstract   Returns a name for the bundle suitable for display to the user.
	@discussion This is performed by asking NSFileManager for the display name of the bundle.
*/
- (NSString *)name;

/*!
	@method
	@abstract	Returns the current internal version of the bundle.
	@discussion	This uses the CFBundleVersion info value. This string is not appropriate for display to users: use -displayVersion instead.
*/
- (NSString *)version;

/*!
	@method
	@abstract	Returns the bundle's version, suitable for display to the user.
	@discussion	If the CFBundleShortVersionString is available and different from the CFBundleVersion, this looks like CFBundleShortVersionString (CFBundleVersion). If the version strings are the same or CFBundleShortVersionString is not defined, this is equivalent to -version.
*/
- (NSString *)displayVersion;

/*!
	@method
	@abstract	Returns a suitable icon for this bundle.
	@discussion	Uses the CFBundleIconFile icon if defined; otherwise, uses the default application icon.
*/
- (NSImage *)icon;

/*!
	@method
	@abstract	Returns whether the application is running from a disk image.
*/
- (BOOL)isRunningFromDiskImage;

/*!
	@method
	@abstract	Returns a profile of the users system useful for statistical purposes.
	@discussion Returns an array of dictionaries; each dictionary represents a piece of data and has keys "key", "visibleKey", "value", and "visibleValue".
*/
- (NSArray *)systemProfile;

- (NSString *)publicDSAKey;
@end

#endif
