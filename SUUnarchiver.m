//
//  SUUnarchiver.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUUnarchiver.h"


@implementation SUUnarchiver

// This method abstracts the types that use a command line tool piping data from stdin.
- (BOOL)_extractArchivePath:archivePath pipingDataToCommand:(NSString *)command
{
	// Get the file size.
	NSNumber *fs = [[[NSFileManager defaultManager] fileAttributesAtPath:archivePath traverseLink:NO] objectForKey:NSFileSize];
	if (fs == nil) { return NO; }
		
	// Thank you, Allan Odgaard!
	// (who wrote the following extraction alg.)
	
	long current = 0;
	FILE *fp, *cmdFP;
	sig_t oldSigPipeHandler = signal(SIGPIPE, SIG_IGN);
	if ((fp = fopen([archivePath UTF8String], "r")))
	{
		setenv("DESTINATION", [[archivePath stringByDeletingLastPathComponent] UTF8String], 1);
		if ((cmdFP = popen([command cString], "w")))
		{
			char buf[32*1024];
			long len;
			while((len = fread(buf, 1, 32 * 1024, fp)))
			{				
				current += len;
				
				NSEvent *event;
				while((event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:nil inMode:NSDefaultRunLoopMode dequeue:YES]))
					[NSApp sendEvent:event];
				
				fwrite(buf, 1, len, cmdFP);
				
				if ([delegate respondsToSelector:@selector(unarchiver:extractedLength:)])
					[delegate unarchiver:self extractedLength:len];
			}
			pclose(cmdFP);
		}
		fclose(fp);
	}	
	signal(SIGPIPE, oldSigPipeHandler);
	return YES;
}

- (BOOL)_extractTAR:(NSString *)archivePath
{
	return [self _extractArchivePath:archivePath pipingDataToCommand:@"tar -xC \"$DESTINATION\""];
}

- (BOOL)_extractTGZ:(NSString *)archivePath
{
	return [self _extractArchivePath:archivePath pipingDataToCommand:@"tar -zxC \"$DESTINATION\""];
}

- (BOOL)_extractTBZ:(NSString *)archivePath
{
	return [self _extractArchivePath:archivePath pipingDataToCommand:@"tar -jxC \"$DESTINATION\""];
}

- (BOOL)_extractZIP:(NSString *)archivePath
{
	return [self _extractArchivePath:archivePath pipingDataToCommand:@"ditto -x -k - \"$DESTINATION\""];
}

- (BOOL)_extractDMG:(NSString *)archivePath
{
	sig_t oldSigChildHandler = signal(SIGCHLD, SIG_DFL);
	// First, we internet-enable the volume.
	NSTask *hdiTask = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/env" arguments:[NSArray arrayWithObjects:@"hdiutil", @"internet-enable", @"-quiet", archivePath, nil]];
	[hdiTask waitUntilExit];
	if ([hdiTask terminationStatus] != 0) { return NO; }
	
	// Now, open the volume; it'll extract into its own directory.
	hdiTask = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/env" arguments:[NSArray arrayWithObjects:@"hdiutil", @"attach", @"-idme", @"-noidmereveal", @"-noidmetrash", @"-noverify", @"-nobrowse", @"-noautoopen", @"-quiet", archivePath, nil]];
	[hdiTask waitUntilExit];
	if ([hdiTask terminationStatus] != 0) { return NO; }
	
	signal(SIGCHLD, oldSigChildHandler);
	
	return YES;
}

- (void)_unarchivePath:(NSString *)path
{
	NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

	// This dictionary associates names of methods responsible for extraction with file extensions.
	// The methods take the path of the archive to extract. They return a BOOL indicating whether
	// we should continue with the update; returns NO if an error occurred.
	NSDictionary *commandDictionary = [NSDictionary dictionaryWithObjectsAndKeys:
																   @"_extractTBZ:", @"tbz",
																   @"_extractTGZ:", @"tgz",
																   @"_extractTAR:", @"tar", 
																   @"_extractZIP:", @"zip", 
																   @"_extractDMG:", @"dmg", nil];
	SEL command = NSSelectorFromString([commandDictionary objectForKey:[path pathExtension]]);
	
	BOOL result;
	if (command)
	{
		NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:command]];
		[invocation setSelector:command];
		[invocation setArgument:&path atIndex:2]; // 0 and 1 are private!
		[invocation invokeWithTarget:self];
		[invocation getReturnValue:&result];
	}
	else
		result = NO;
	
	if (result)
	{
		if ([delegate respondsToSelector:@selector(unarchiverDidFinish:)])
			[delegate performSelector:@selector(unarchiverDidFinish:) withObject:self];
	}
	else
	{
		if ([delegate respondsToSelector:@selector(unarchiverDidFail:)])
			[delegate performSelector:@selector(unarchiverDidFail:) withObject:self];
	}

	[pool release];
}

- (void)unarchivePath:(NSString *)path
{
	[NSThread detachNewThreadSelector:@selector(_unarchivePath:) toTarget:self withObject:path];
}

- (void)setDelegate:del
{
	delegate = del;
}

@end
