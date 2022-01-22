//
//  SUDiskImageUnarchiver.m
//  Sparkle
//
//  Created by Andy Matuschak on 6/16/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUDiskImageUnarchiver.h"
#import "SUUnarchiverNotifier.h"
#import "SULog.h"


#include "AppKitPrevention.h"

@interface SUDiskImageUnarchiver ()

@property (nonatomic, copy, readonly) NSString *archivePath;
@property (nullable, nonatomic, copy, readonly) NSString *decryptionPassword;

@end

@implementation SUDiskImageUnarchiver

@synthesize archivePath = _archivePath;
@synthesize decryptionPassword = _decryptionPassword;

+ (BOOL)canUnarchivePath:(NSString *)path
{
    return [[path pathExtension] isEqualToString:@"dmg"];
}

+ (BOOL)mustValidateBeforeExtraction
{
    return NO;
}

- (instancetype)initWithArchivePath:(NSString *)archivePath decryptionPassword:(nullable NSString *)decryptionPassword
{
    self = [super init];
    if (self != nil) {
        _archivePath = [archivePath copy];
        _decryptionPassword = [decryptionPassword copy];
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
- (void)extractDMGWithNotifier:(SUUnarchiverNotifier *)notifier
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
        // Note: this check does not follow symbolic links, which is what we want
		while ([[NSURL fileURLWithPath:mountPoint] checkResourceIsReachableAndReturnError:NULL]);
        
        NSData *promptData = [NSData dataWithBytes:"yes\n" length:4];
        
        NSMutableArray *arguments = [@[@"attach", self.archivePath, @"-mountpoint", mountPoint, /*@"-noverify",*/ @"-nobrowse", @"-noautoopen"] mutableCopy];
        
        if (self.decryptionPassword) {
            NSMutableData *passwordData = [[self.decryptionPassword dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
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
            
            if (@available(macOS 10.13, *)) {
                if (![task launchAndReturnError:&error]) {
                    goto reportError;
                }
            } else {
                @try {
                    [task launch];
                } @catch (NSException *) {
                    goto reportError;
                }
            }
            
            [notifier notifyProgress:0.125];

            [inputPipe.fileHandleForWriting writeData:promptData];
            
            if (@available(macOS 10.15, *)) {
                if (![inputPipe.fileHandleForWriting writeData:promptData error:&error]) {
                    goto reportError;
                }
            } else {
                @try {
                    [inputPipe.fileHandleForWriting writeData:promptData];
                } @catch (NSException *) {
                    goto reportError;
                }
            }
            
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
            NSString *toPath = [[self.archivePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:item];
            
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
            
            
            if (@available(macOS 10.13, *)) {
                NSError *launchCleanupError = nil;
                if (![task launchAndReturnError:&launchCleanupError]) {
                    SULog(SULogLevelError, @"Failed to unmount %@", mountPoint);
                    SULog(SULogLevelError, @"Error: %@", launchCleanupError);
                }
            } else {
                @try {
                    [task launch];
                } @catch (NSException *exception) {
                    SULog(SULogLevelError, @"Failed to unmount %@", mountPoint);
                    SULog(SULogLevelError, @"Exception: %@", exception);
                }
            }
        } else {
            SULog(SULogLevelError, @"Can't mount DMG %@", self.archivePath);
        }
    }
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], self.archivePath]; }

@end
