//
//  SUBinaryDeltaUnarchiver.m
//  Sparkle
//
//  Created by Mark Rowe on 2009-06-03.
//  Copyright 2009 Mark Rowe. All rights reserved.
//

#import "SUBinaryDeltaUnarchiver.h"
#import "SUBinaryDeltaApply.h"
#import "SUUnarchiver_Private.h"
#import "SUHost.h"
#import "NTSynchronousTask.h"

@implementation SUBinaryDeltaUnarchiver

+ (BOOL)_canUnarchivePath:(NSString *)path
{
	return [[path pathExtension] isEqualToString:@"delta"];
}

- (void)start
{
	[NSThread detachNewThreadSelector:@selector(_applyBinaryDelta) toTarget:self withObject:nil];
}

- (void)_applyBinaryDelta
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	NSString *sourcePath = [[updateHost bundle] bundlePath];
	NSString *targetPath = [[archivePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:[sourcePath lastPathComponent]];

	int result = applyBinaryDelta(sourcePath, targetPath, archivePath);
	if (!result)
		[self performSelectorOnMainThread:@selector(_notifyDelegateOfSuccess) withObject:nil waitUntilDone:NO];
	else
		[self performSelectorOnMainThread:@selector(_notifyDelegateOfFailure) withObject:nil waitUntilDone:NO];

	[pool drain];
}

+ (void)load
{
	[self _registerImplementation:self];
}

@end
