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
#include <CoreServices/CoreServices.h>
#import "SUXPCInstaller.h"

@implementation SUDiskImageUnarchiver

+ (BOOL)canUnarchivePath:(NSString *)path
{
    return [[path pathExtension] isEqualToString:@"dmg"];
}

// Called on a non-main thread.
- (void)extractDMG
{
	@autoreleasepool {
        [self extractDMGWithPassword:nil];
    }
}

// Called on a non-main thread.
- (void)extractDMGWithPassword:(NSString *)__unused password
{
	@autoreleasepool {
        BOOL mountedSuccessfully = NO;

        SULog(@"Extracting %@ as a DMG", self.archivePath);

        // We have to declare these before a goto to prevent an error under ARC.
        // No, we cannot have them in the dispatch_async calls, as the goto "jump enters
        // lifetime of block which strongly captures a variable"
        dispatch_block_t delegateFailure = ^{
            [self notifyDelegateOfFailure];
        };
        dispatch_block_t delegateSuccess = ^{
            [self notifyDelegateOfSuccess];
        };

        // get a unique mount point path
        NSString *mountPoint = nil;
        do
		{
            // Using NSUUID would make creating UUIDs be done in Cocoa,
            // and thus managed under ARC. Sadly, the class is in 10.8 and later.
            CFUUIDRef uuid = CFUUIDCreate(NULL);
			if (uuid)
			{
                NSString *uuidString = CFBridgingRelease(CFUUIDCreateString(NULL, uuid));
				if (uuidString)
				{
                    mountPoint = [@"/Volumes" stringByAppendingPathComponent:uuidString];
                }
                CFRelease(uuid);
            }
		}
		while ([[NSFileManager defaultManager] fileExistsAtPath:mountPoint]);

        NSData *promptData = nil;
        promptData = [NSData dataWithBytes:"yes\n" length:4];

        NSString *hdiutilPath = @"/usr/bin/hdiutil";
        NSString *currentDirPath = @"/";
        NSArray *arguments = @[@"attach", self.archivePath, @"-mountpoint", mountPoint, /*@"-noverify",*/ @"-nobrowse", @"-noautoopen"];

        if (self.decryptionPassword) {
            NSMutableData *passwordData = [[self.decryptionPassword dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
            // From the hdiutil docs:
            // read a null-terminated passphrase from standard input
            //
            // Add the null terminator, then the newline
            [passwordData appendData:[NSData dataWithBytes:"\0" length:1]];
            [passwordData appendData:promptData];
            promptData = passwordData;

            arguments = [arguments arrayByAddingObject:@"-stdinpass"];
        }

        BOOL shouldUseXPC = SUShouldUseXPCInstaller();
        
        __block NSData *output = nil;
        __block NSInteger taskResult = -1;
		@try
		{
            if (shouldUseXPC)
            {
                [SUXPCInstaller launchTaskWithPath:hdiutilPath arguments:arguments environment:nil currentDirectoryPath:currentDirPath inputData:promptData waitUntilDone:YES completionHandler:^(int result, NSData *outputData) {
                    taskResult = (NSInteger)result;
                    output = [outputData copy];
                }];
            }
            else
            {
                NTSynchronousTask *task = [[NTSynchronousTask alloc] init];

                [task run:hdiutilPath directory:currentDirPath withArgs:arguments input:promptData];

                taskResult = [task result];
                output = [[task output] copy];
            }
        }
        @catch (NSException *)
        {
            goto reportError;
        }

		if (taskResult != 0)
		{
            NSString *resultStr = output ? [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] : nil;
            SULog(@"hdiutil failed with code: %ld data: <<%@>>", (long)taskResult, resultStr);
            goto reportError;
        }
        mountedSuccessfully = YES;

        // Now that we've mounted it, we need to copy out its contents.
        if (shouldUseXPC)
        {
            NSError *error = nil;
            [SUXPCInstaller copyPathContent:mountPoint toDirectory:[self.archivePath stringByDeletingLastPathComponent] error:&error];
            
            if (nil != error)
            {
                SULog(@"Couldn't copy volume content: %ld - %@", error.code, error.localizedDescription);
                goto reportError;
            }
        }
        else
        {
            NSFileManager *manager = [[NSFileManager alloc] init];
            NSError *error = nil;
            NSArray *contents = [manager contentsOfDirectoryAtPath:mountPoint error:&error];
            if (error)
            {
                SULog(@"Couldn't enumerate contents of archive mounted at %@: %@", mountPoint, error);
                goto reportError;
            }

            for (NSString *item in contents)
            {
                NSString *fromPath = [mountPoint stringByAppendingPathComponent:item];
                NSString *toPath = [[self.archivePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:item];

                // We skip any files in the DMG which are not readable.
                if (![manager isReadableFileAtPath:fromPath]) {
                    continue;
                }

                SULog(@"copyItemAtPath:%@ toPath:%@", fromPath, toPath);

                if (![manager copyItemAtPath:fromPath toPath:toPath error:&error])
                {
                    SULog(@"Couldn't copy item: %@ : %@", error, error.userInfo ? error.userInfo : @"");
                    goto reportError;
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), delegateSuccess);
        goto finally;

    reportError:
        dispatch_async(dispatch_get_main_queue(), delegateFailure);

    finally:
        if (mountedSuccessfully)
        {
            arguments = @[@"detach", mountPoint, @"-force"];
            if (shouldUseXPC)
            {
                [SUXPCInstaller launchTaskWithPath:hdiutilPath arguments:arguments environment:nil currentDirectoryPath:nil inputData:nil waitUntilDone:NO completionHandler:nil];
            }
            else
            {
                [NSTask launchedTaskWithLaunchPath:hdiutilPath arguments:arguments];
            }
        }
        else
        {
            SULog(@"Can't mount DMG %@", self.archivePath);
        }
    }
}

- (void)start
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		[self extractDMG];
    });
}

+ (void)load
{
    [self registerImplementation:self];
}

- (BOOL)isEncrypted:(NSData *)resultData
{
    BOOL result = NO;
	if(resultData)
	{
        NSString *data = [[NSString alloc] initWithData:resultData encoding:NSUTF8StringEncoding];

        if ((data != nil) && !NSEqualRanges([data rangeOfString:@"passphrase-count"], NSMakeRange(NSNotFound, 0)))
		{
            result = YES;
        }
    }
    return result;
}

@end
