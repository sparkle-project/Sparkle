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
	@autoreleasepool {
		NSString *sourcePath = [[updateHost bundle] bundlePath];
		NSString *targetPath = [[archivePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:[sourcePath lastPathComponent]];

		int result = applyBinaryDelta(sourcePath, targetPath, archivePath);
		if (!result) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[self notifyDelegateOfSuccess];
			});
		}
		else {
			dispatch_async(dispatch_get_main_queue(), ^{
				[self notifyDelegateOfFailure];
			});
		}
	}
}

- (void)start
{
	dispatch_async(dispatch_get_global_queue(0, 0), ^{
		[self applyBinaryDelta];
	});
}

+ (void)load
{
	[self registerImplementation:self];
}

@end
