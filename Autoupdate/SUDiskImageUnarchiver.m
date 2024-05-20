//
//  SUDiskImageUnarchiver.m
//  Sparkle
//
//  Created by Andy Matuschak on 6/16/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#if SPARKLE_BUILD_DMG_SUPPORT

#import "SUDiskImageUnarchiver.h"
#import "SUUnarchiverNotifier.h"
#import "SULog.h"


#include "AppKitPrevention.h"

@implementation SUDiskImageUnarchiver
{
    NSString *_archivePath;
    NSString *_decryptionPassword;
    NSString *_extractionDirectory;
}

+ (BOOL)canUnarchivePath:(NSString *)path
{
    return [[path pathExtension] isEqualToString:@"dmg"];
}

+ (BOOL)mustValidateBeforeExtraction
{
    return NO;
}

- (instancetype)initWithArchivePath:(NSString *)archivePath extractionDirectory:(NSString *)extractionDirectory decryptionPassword:(nullable NSString *)decryptionPassword
{
    self = [super init];
    if (self != nil) {
        _archivePath = [archivePath copy];
        _decryptionPassword = [decryptionPassword copy];
        _extractionDirectory = [extractionDirectory copy];
    }
    return self;
}

- (void)unarchiveWithCompletionBlock:(void (^)(NSError * _Nullable))completionBlock progressBlock:(void (^ _Nullable)(double))progressBlock
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SUUnarchiverNotifier *notifier = [[SUUnarchiverNotifier alloc] initWithCompletionBlock:completionBlock progressBlock:progressBlock];
        [self extractDMGWithNotifier:notifier];
    });
}

// Called on a non-main thread.
- (void)extractDMGWithNotifier:(SUUnarchiverNotifier *)notifier SPU_OBJC_DIRECT
{
	@autoreleasepool {
        BOOL mountedSuccessfully = NO;
        
        // get a unique mount point path
        NSString *mountPoint = nil;
        NSFileManager *manager;
        NSError *error = nil;
        NSArray *contents = nil;
        do
		{
            NSString *uuidString = [[NSUUID UUID] UUIDString];
            mountPoint = [@"/Volumes" stringByAppendingPathComponent:uuidString];
		}
        // Note: this check does not follow symbolic links, which is what we want
		while ([[NSURL fileURLWithPath:mountPoint] checkResourceIsReachableAndReturnError:NULL]);
        
        NSData *promptData = [NSData dataWithBytes:"yes\n" length:4];
        
        NSMutableArray *arguments = [@[@"attach", _archivePath, @"-mountpoint", mountPoint, /*@"-noverify",*/ @"-nobrowse", @"-noautoopen"] mutableCopy];
        
        if (_decryptionPassword) {
            NSMutableData *passwordData = [[_decryptionPassword dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
            // From the hdiutil docs:
            // read a null-terminated passphrase from standard input
            //
            // Add the null terminator, then the newline
            [passwordData appendData:[NSData dataWithBytes:"\0" length:1]];
            [passwordData appendData:promptData];
            promptData = passwordData;
            
            [arguments addObject:@"-stdinpass"];
        }
        
        NSData *output = nil;
        NSInteger taskResult = -1;
        
        {
            NSTask *task = [[NSTask alloc] init];
            task.launchPath = @"/usr/bin/hdiutil";
            task.currentDirectoryPath = @"/";
            task.arguments = arguments;
            
            NSPipe *inputPipe = [NSPipe pipe];
            NSPipe *outputPipe = [NSPipe pipe];
            
            task.standardInput = inputPipe;
            task.standardOutput = outputPipe;
            
            NSFileHandle *fileStdHandle = outputPipe.fileHandleForReading;
            NSMutableData *currentOutput = [NSMutableData data];
            
            fileStdHandle.readabilityHandler = ^(NSFileHandle *file) {
                [currentOutput appendData:file.availableData];
            };
            
            dispatch_semaphore_t terminationSemaphore = dispatch_semaphore_create(0);
            task.terminationHandler = ^(NSTask *__unused terminatingTask) {
                fileStdHandle.readabilityHandler = nil;
                
                dispatch_semaphore_signal(terminationSemaphore);
            };
            
            if (![task launchAndReturnError:&error]) {
                goto reportError;
            }
            
            [notifier notifyProgress:0.125];
            
            if (@available(macOS 10.15, *)) {
                if (![inputPipe.fileHandleForWriting writeData:promptData error:&error]) {
                    goto reportError;
                }
            }
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_15
            else
            {
                @try {
                    [inputPipe.fileHandleForWriting writeData:promptData];
                } @catch (NSException *) {
                    goto reportError;
                }
            }
#endif
            
            [inputPipe.fileHandleForWriting closeFile];
            
            dispatch_semaphore_wait(terminationSemaphore, DISPATCH_TIME_FOREVER);
            output = [currentOutput copy];
            
            taskResult = task.terminationStatus;
        }
        
        [notifier notifyProgress:0.5];

		if (taskResult != 0)
		{
            NSString *resultStr = output ? [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] : nil;
            SULog(SULogLevelError, @"hdiutil failed with code: %ld data: <<%@>>", (long)taskResult, resultStr);
            goto reportError;
        }
        mountedSuccessfully = YES;
        
        // Now that we've mounted it, we need to copy out its contents.
        manager = [[NSFileManager alloc] init];
        contents = [manager contentsOfDirectoryAtPath:mountPoint error:&error];
        if (contents == nil)
        {
            SULog(SULogLevelError, @"Couldn't enumerate contents of archive mounted at %@: %@", mountPoint, error);
            goto reportError;
        }

        double itemsCopied = 0;
        double totalItems = (double)[contents count];

		for (NSString *item in contents)
		{
            NSString *fromPath = [mountPoint stringByAppendingPathComponent:item];
            NSString *toPath = [_extractionDirectory stringByAppendingPathComponent:item];
            
            itemsCopied += 1.0;
            [notifier notifyProgress:0.5 + itemsCopied/(totalItems*2.0)];
            
            // We skip any files in the DMG which are not readable but include the item in the progress
            if (![manager isReadableFileAtPath:fromPath]) {
                continue;
            }

            SULog(SULogLevelDefault, @"copyItemAtPath:%@ toPath:%@", fromPath, toPath);

			if (![manager copyItemAtPath:fromPath toPath:toPath error:&error])
			{
                goto reportError;
            }
        }
        
        [notifier notifySuccess];
        goto finally;
        
    reportError:
        [notifier notifyFailureWithError:error];

    finally:
        if (mountedSuccessfully) {
            NSTask *task = [[NSTask alloc] init];
            task.launchPath = @"/usr/bin/hdiutil";
            task.arguments = @[@"detach", mountPoint, @"-force"];
            task.standardOutput = [NSPipe pipe];
            task.standardError = [NSPipe pipe];
            
            NSError *launchCleanupError = nil;
            if (![task launchAndReturnError:&launchCleanupError]) {
                SULog(SULogLevelError, @"Failed to unmount %@", mountPoint);
                SULog(SULogLevelError, @"Error: %@", launchCleanupError);
            }
        } else {
            SULog(SULogLevelError, @"Can't mount DMG %@", _archivePath);
        }
    }
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], _archivePath]; }

@end

#endif
