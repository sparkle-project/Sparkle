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
#import "SULog.h"
#import <CoreServices/CoreServices.h>

@implementation SUDiskImageUnarchiver

+ (BOOL)canUnarchivePath:(NSString *)path
{
	return [[path pathExtension] isEqualToString:@"dmg"];
}

// Called on a non-main thread.
- (void)extractDMG
{
	
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    NSData *result = [NTSynchronousTask task:@"/usr/bin/hdiutil" directory:@"/" withArgs:[NSArray arrayWithObjects: @"isencrypted", archivePath, nil] input:NULL];
	if([self isEncrypted:result] && [delegate respondsToSelector:@selector(unarchiver:requiresPasswordReturnedViaInvocation:)]) {
        [self performSelectorOnMainThread:@selector(requestPasswordFromDelegate) withObject:nil waitUntilDone:NO];
    } else {
        [self extractDMGWithPassword:nil];
    }
    
    [pool release];
}

// Called on a non-main thread.
- (void)extractDMGWithPassword:(NSString *)password
{
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
	BOOL mountedSuccessfully = NO;
	
	SULog(@"Extracting %@ as a DMG", archivePath);
	
	// get a unique mount point path
	NSString *mountPointName = nil;
	NSString *mountPoint = nil;
	FSRef tmpRef;
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
	}
	while (noErr == FSPathMakeRefWithOptions((UInt8 *)[mountPoint fileSystemRepresentation], kFSPathMakeRefDoNotFollowLeafSymlink, &tmpRef, NULL));

    NSData *promptData = nil;
    if (password) {
        NSString *data = [NSString stringWithFormat:@"%@\nyes\n", password];
        const char *bytes = [data cStringUsingEncoding:NSUTF8StringEncoding];
        NSUInteger length = [data lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
        promptData = [NSData dataWithBytes:bytes length:length];
	}
	else
		promptData = [NSData dataWithBytes:"yes\n" length:4];
	
    NSArray* arguments = [NSArray arrayWithObjects:@"attach", archivePath, @"-mountpoint", mountPoint, /*@"-noverify",*/ @"-nobrowse", @"-noautoopen", nil];
    
    NSData *output = nil;
	NSInteger taskResult = -1;
	@try
	{
		NTSynchronousTask* task = [[NTSynchronousTask alloc] init];
		
		[task run:@"/usr/bin/hdiutil" directory:@"/" withArgs:arguments input:promptData];
		
		taskResult = [task result];
		output = [[[task output] copy] autorelease];
        [task release];
	}
	@catch (NSException *localException)
	{ 
		goto reportError;
	}
	
	if (taskResult != 0)
	{
		NSString*	resultStr = output ? [[[NSString alloc] initWithData: output encoding: NSUTF8StringEncoding] autorelease] : nil;
        if (password != nil && [resultStr rangeOfString:@"Authentication error"].location != NSNotFound && [delegate respondsToSelector:@selector(unarchiver:requiresPasswordReturnedViaInvocation:)]) {
            [self performSelectorOnMainThread:@selector(requestPasswordFromDelegate) withObject:nil waitUntilDone:NO];
            goto finally;
        } else {
            SULog( @"hdiutil failed with code: %d data: <<%@>>", taskResult, resultStr );
            goto reportError;
        }
	}
	mountedSuccessfully = YES;
	
	// Now that we've mounted it, we need to copy out its contents.
	if (floor(NSAppKitVersionNumber) > NSAppKitVersionNumber10_6) {
		// On 10.7 and later we don't want to use the File Manager API and instead want to use NSFileManager (fixes #827357).
		NSFileManager *manager = [[[NSFileManager alloc] init] autorelease];
        NSError *error = nil;
        NSArray *contents = [manager contentsOfDirectoryAtPath:mountPoint error:&error];
        if (error)
        {
            SULog(@"Couldn't enumerate contents of archive mounted at %@: %@", mountPoint, error);
            goto reportError;
        }
        
        NSEnumerator *contentsEnumerator = [contents objectEnumerator];
        NSString *item;
        while ((item = [contentsEnumerator nextObject]))
        {
            NSString *fromPath = [mountPoint stringByAppendingPathComponent:item];
            NSString *toPath = [[archivePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:item];
            
            // We skip any files in the DMG which are not readable.
            if (![manager isReadableFileAtPath:fromPath])
                continue;
            
            SULog(@"copyItemAtPath:%@ toPath:%@", fromPath, toPath);
            
            if (![manager copyItemAtPath:fromPath toPath:toPath error:&error])
            {
                SULog(@"Couldn't copy item: %@ : %@", error, error.userInfo ? error.userInfo : @"");
                goto reportError;
            }
        }
	}
	else {
		FSRef srcRef, dstRef;
		OSStatus err;
		err = FSPathMakeRef((UInt8 *)[mountPoint fileSystemRepresentation], &srcRef, NULL);
		if (err != noErr) goto reportError;
		err = FSPathMakeRef((UInt8 *)[[archivePath stringByDeletingLastPathComponent] fileSystemRepresentation], &dstRef, NULL);
		if (err != noErr) goto reportError;
		
		err = FSCopyObjectSync(&srcRef, &dstRef, (CFStringRef)mountPointName, NULL, kFSFileOperationSkipSourcePermissionErrors);
		if (err != noErr) goto reportError;
	}
	
	[self performSelectorOnMainThread:@selector(notifyDelegateOfSuccess) withObject:nil waitUntilDone:NO];
	goto finally;
	
reportError:
	[self performSelectorOnMainThread:@selector(notifyDelegateOfFailure) withObject:nil waitUntilDone:NO];

finally:
	if (mountedSuccessfully)
		[NSTask launchedTaskWithLaunchPath:@"/usr/bin/hdiutil" arguments:[NSArray arrayWithObjects:@"detach", mountPoint, @"-force", nil]];
	else
		SULog(@"Can't mount DMG %@",archivePath);
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

- (BOOL)isEncrypted:(NSData*)resultData
{
	BOOL result = NO;
	if(resultData)
	{
		NSString *data = [NSString stringWithCString:(char*)[resultData bytes] encoding:NSUTF8StringEncoding];
		if (!NSEqualRanges([data rangeOfString:@"passphrase-count"], NSMakeRange(NSNotFound, 0))) 
		{
			result = YES;
		}
	}
	return result;
}

- (void)requestPasswordFromDelegate
{
    NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(continueWithPassword:)]];
    [invocation setSelector:@selector(continueWithPassword:)];
    [invocation setTarget:self];
    [invocation retainArguments];
    [delegate unarchiver:self requiresPasswordReturnedViaInvocation:invocation];
}

- (void)continueWithPassword:(NSString *)password
{
    [NSThread detachNewThreadSelector:@selector(extractDMGWithPassword:) toTarget:self withObject:password];
}

@end
