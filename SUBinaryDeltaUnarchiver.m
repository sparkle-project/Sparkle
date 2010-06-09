//
//  SUBinaryDeltaUnarchiver.m
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-03.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#import "SUBinaryDeltaCommon.h"
#import "SUBinaryDeltaUnarchiver.h"
#import "SUBinaryDeltaApply.h"
#import "SUUnarchiver_Private.h"
#import "SUHost.h"
#import "NTSynchronousTask.h"

@implementation SUBinaryDeltaUnarchiver

+ (BOOL)canUnarchivePath:(NSString *)path
{
	return binaryDeltaSupported() && [[path pathExtension] isEqualToString:@"delta"];
}

- (void)applyBinaryDelta
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *sourcePath = [[updateHost bundle] bundlePath];
	NSString *targetPath = [[archivePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:[sourcePath lastPathComponent]];

	int result = applyBinaryDelta(sourcePath, targetPath, archivePath);
	if (!result)
		[self performSelectorOnMainThread:@selector(notifyDelegateOfSuccess) withObject:nil waitUntilDone:NO];
	else
		[self performSelectorOnMainThread:@selector(notifyDelegateOfFailure) withObject:nil waitUntilDone:NO];

	[pool drain];
}

- (void)start
{
	[NSThread detachNewThreadSelector:@selector(applyBinaryDelta) toTarget:self withObject:nil];
}

+ (void)load
{
	[self registerImplementation:self];
}

@end
