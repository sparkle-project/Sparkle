//
//  NSFileManager+ExtendedAttributes.m
//  Sparkle
//
//  Created by Mark Mentovai on 2008-01-22.
//  Copyright 2008 Mark Mentovai.  All rights reserved.
//

#import "NSFileManager+ExtendedAttributes.h"

#include <dlfcn.h>
#include <errno.h>

// Extended attribute support was introduced in Mac OS X 10.4 ("Tiger").
// If building with an earlier SDK, provide definitions needed to handle
// extended attributes at runtime.
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4  // SDK >= 10.4
#include <sys/xattr.h>
#else  // SDK >= 10.4
#define XATTR_NOFOLLOW 1
#endif  // SDK >= 10.4

@implementation NSFileManager (MMExtendedAttributes)

- (int)removeXAttr:(const char*)name
          fromFile:(NSString*)file
           options:(int)options
{
	typedef int (*removexattr_type)(const char*, const char*, int);
#if MAC_OS_X_VERSION_MAX_ALLOWED >= MAC_OS_X_VERSION_10_4  // SDK >= 10.4
	// Reference removexattr directly, it's in the SDK.
	static removexattr_type removexattr_func = removexattr;
#else  // SDK >= 10.4
	// removexattr isn't in this SDK, look it up at runtime.
	static removexattr_type removexattr_func = NULL;
	static BOOL didSymbolLookup = NO;
	if (!didSymbolLookup) {
		didSymbolLookup = YES;
		removexattr_func = dlsym(RTLD_NEXT, "removexattr");
	}
#endif  // SDK >= 10.4
	
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_4  // DT < 10.4
	// Make sure that the symbol is present.  This checks the deployment
	// target instead of the SDK so that it's able to catch dlsym failures
	// as well as the null symbol that would result from building with the
	// 10.4 SDK and a lower deployment target, and running on 10.3.
	if (!removexattr_func) {
		errno = ENOSYS;
		return -1;
	}
#endif  // DT < 10.4
	
	const char* path = NULL;
	@try {
		path = [file fileSystemRepresentation];
	}
	@catch (id exception) {
		// -[NSString fileSystemRepresentation] throws an exception if it's
		// unable to convert the string to something suitable.  Map that to
		// EDOM, "argument out of domain", which sort of conveys that there
		// was a conversion failure.
		errno = EDOM;
		return -1;
	}
	
	return removexattr_func(path, name, options);
}

- (void)releaseFromQuarantine:(NSString*)root
{
	const char* quarantineAttribute = "com.apple.quarantine";
	const int removeXAttrOptions = XATTR_NOFOLLOW;
	
	[self removeXAttr:quarantineAttribute
			 fromFile:root
			  options:removeXAttrOptions];
	
	// Only recurse if it's actually a directory.  Don't recurse into a
	// root-level symbolic link.
	NSDictionary* rootAttributes =
	[self fileAttributesAtPath:root traverseLink:NO];
	NSString* rootType = [rootAttributes objectForKey:NSFileType];
	
	if (rootType == NSFileTypeDirectory) {
		// The NSDirectoryEnumerator will avoid recursing into any contained
		// symbolic links, so no further type checks are needed.
		NSDirectoryEnumerator* directoryEnumerator = [self enumeratorAtPath:root];
		NSString* file = nil;
		while ((file = [directoryEnumerator nextObject])) {
			[self removeXAttr:quarantineAttribute
					 fromFile:[root stringByAppendingPathComponent:file]
					  options:removeXAttrOptions];
		}
	}
}

@end
