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
#import <CoreServices/CoreServices.h>

@implementation SUDiskImageUnarchiver

+ (BOOL)canUnarchivePath:(NSString *)path
{
	return [[path pathExtension] isEqualToString:@"dmg"];
}

- (void)extractDMG
{		
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	BOOL mountedSuccessfully = NO;
	NSFileManager *fm = [[[NSFileManager alloc] init] autorelease];
	NSGarbageCollector *dc = [NSGarbageCollector defaultCollector];
	NSError *anError = nil;
	
	// get a unique mount point path
	NSString *mountPointName = nil;
	NSString *mountPoint = nil;
	FSRef tmpRef;
	BOOL cont = YES;
	do
	{
		CFUUIDRef uuid = CFUUIDCreate(NULL);
		if (uuid)
		{
			CFStringRef uuidString = CFUUIDCreateString(NULL, uuid);
			if (uuidString)
			{
				mountPoint = [@"/Volumes" stringByAppendingPathComponent:(NSString*)uuidString];
				CFRelease(uuidString);
			}
			CFRelease(uuid);
		}
		
		[dc disableCollectorForPointer:mountPoint];
		cont =  (noErr == FSPathMakeRefWithOptions((UInt8 *)[mountPoint fileSystemRepresentation], kFSPathMakeRefDoNotFollowLeafSymlink, &tmpRef, NULL));
		[dc enableCollectorForPointer:mountPoint];
	}
	while (cont);
	
	NSArray* arguments = [NSArray arrayWithObjects:@"attach", archivePath, @"-mountpoint", mountPoint, @"-noverify", @"-nobrowse", @"-noautoopen", nil];
	// set up a pipe and push "yes" (y works too), this will accept any license agreement crap
	// not every .dmg needs this, but this will make sure it works with everyone
	NSData* yesData = [[[NSData alloc] initWithBytes:"yes\n" length:4] autorelease];
	
	NSData *result = [NTSynchronousTask task:@"/usr/bin/hdiutil" directory:@"/" withArgs:arguments input:yesData];
	if (!result) goto reportError;
	mountedSuccessfully = YES;
	
	// Now that we've mounted it, we need to copy out its contents.
	NSString *dstPath = [[archivePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:mountPointName];
	if (![fm copyItemAtPath:mountPoint toPath:dstPath error:&anError])
		goto reportError;
	
	[self performSelectorOnMainThread:@selector(notifyDelegateOfSuccess) withObject:nil waitUntilDone:NO];
	goto finally;
	
reportError:
	[self performSelectorOnMainThread:@selector(notifyDelegateOfFailure) withObject:nil waitUntilDone:NO];

finally:
	if (mountedSuccessfully)
		[NSTask launchedTaskWithLaunchPath:@"/usr/bin/hdiutil" arguments:[NSArray arrayWithObjects:@"detach", mountPoint, @"-force", nil]];
	[pool drain];
}

- (void)start
{
	[NSThread detachNewThreadSelector:@selector(extractDMG) toTarget:self withObject:nil];
}

+ (void)load
{
	[self registerImplementation:self];
}

@end
