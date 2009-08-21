//
//  SUDiskImageUnarchiver.m
//  Sparkle
//
//  Created by Andy Matuschak on 6/16/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUDiskImageUnarchiver.h"
#import "SUUnarchiver_Private.h"
#import "NTSynchronousTask.h"

@implementation SUDiskImageUnarchiver

+ (BOOL)_canUnarchivePath:(NSString *)path
{
	return [[path pathExtension] isEqualToString:@"dmg"];
}

- (void)start
{
	[NSThread detachNewThreadSelector:@selector(_extractDMG) toTarget:self withObject:nil];
}

- (void)_extractDMG
{		
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	BOOL mountedSuccessfully = NO;
	
	// get a unique mount point path
	NSString *mountPoint = [@"/Volumes" stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
	
	if ([[NSFileManager defaultManager] fileExistsAtPath:mountPoint]) goto reportError;

	// create mount point folder
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
    [[NSFileManager defaultManager] createDirectoryAtPath:mountPoint attributes:nil];
#else
	[[NSFileManager defaultManager] createDirectoryAtPath:mountPoint withIntermediateDirectories:YES attributes:nil error:NULL];
#endif
	if (![[NSFileManager defaultManager] fileExistsAtPath:mountPoint]) goto reportError;

	NSArray* arguments = [NSArray arrayWithObjects:@"attach", archivePath, @"-mountpoint", mountPoint, @"-noverify", @"-nobrowse", @"-noautoopen", nil];
	// set up a pipe and push "yes" (y works too), this will accept any license agreement crap
	// not every .dmg needs this, but this will make sure it works with everyone
	NSData* yesData = [[[NSData alloc] initWithBytes:"yes\n" length:4] autorelease];
	
	NSData *result = [NTSynchronousTask task:@"/usr/bin/hdiutil" directory:@"/" withArgs:arguments input:yesData];
	if (!result) goto reportError;
	mountedSuccessfully = YES;
	
	// Now that we've mounted it, we need to copy out its contents.
	NSString *targetPath = [[archivePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:[mountPoint lastPathComponent]];
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
    if (![[NSFileManager defaultManager] createDirectoryAtPath:targetPath attributes:nil]) goto reportError;
#else
	if (![[NSFileManager defaultManager] createDirectoryAtPath:targetPath withIntermediateDirectories:YES attributes:nil error:NULL]) goto reportError;
#endif
	
	// We can't just copyPath: from the volume root because that always fails. Seems to be a bug.
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
    id subpathEnumerator = [[[NSFileManager defaultManager] directoryContentsAtPath:mountPoint] objectEnumerator];
#else
	id subpathEnumerator = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:mountPoint error:NULL] objectEnumerator];
#endif
	NSString *currentSubpath;
	while ((currentSubpath = [subpathEnumerator nextObject]))
	{
		NSString *currentFullPath = [mountPoint stringByAppendingPathComponent:currentSubpath];
		// Don't bother trying (and failing) to copy out files we can't read. That's not going to be the app anyway.
		if (![[NSFileManager defaultManager] isReadableFileAtPath:currentFullPath]) continue;
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
        if (![[NSFileManager defaultManager] copyPath:currentFullPath toPath:[targetPath stringByAppendingPathComponent:currentSubpath] handler:nil])
#else
		if (![[NSFileManager defaultManager] copyItemAtPath:currentFullPath toPath:[targetPath stringByAppendingPathComponent:currentSubpath] error:NULL])
#endif
			goto reportError;
	}
			
	[self performSelectorOnMainThread:@selector(_notifyDelegateOfSuccess) withObject:nil waitUntilDone:NO];
	goto finally;
	
reportError:
	[self performSelectorOnMainThread:@selector(_notifyDelegateOfFailure) withObject:nil waitUntilDone:NO];

finally:
	if (mountedSuccessfully)
		[NSTask launchedTaskWithLaunchPath:@"/usr/bin/hdiutil" arguments:[NSArray arrayWithObjects:@"detach", mountPoint, @"-force", nil]];
	else
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_5
        [[NSFileManager defaultManager] removeFileAtPath:mountPoint handler:nil];
#else
		[[NSFileManager defaultManager] removeItemAtPath:mountPoint error:NULL];
#endif
	[pool drain];
}

+ (void)load
{
	[self _registerImplementation:self];
}

@end
