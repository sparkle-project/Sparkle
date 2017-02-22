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

+ (BOOL)unsafeIfArchiveIsNotValidated
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
        NSError *error;
        NSArray *contents;
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
        
        NSData *promptData = nil;
        promptData = [NSData dataWithBytes:"yes\n" length:4];
        
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
        @try
        {
            NSTask *task = [[NSTask alloc] init];
            task.launchPath = @"/usr/bin/hdiutil";
            task.currentDirectoryPath = @"/";
            task.arguments = arguments;
            
            NSPipe *inputPipe = [NSPipe pipe];
            NSPipe *outputPipe = [NSPipe pipe];
            
            task.standardInput = inputPipe;
            task.standardOutput = outputPipe;
            
            [task launch];
            
            [notifier notifyProgress:0.125];

            [inputPipe.fileHandleForWriting writeData:promptData];
            [inputPipe.fileHandleForWriting closeFile];
            
            // Read data to end *before* waiting until the task ends so we don't deadlock if the stdout buffer becomes full if we haven't consumed from it
            output = [outputPipe.fileHandleForReading readDataToEndOfFile];
            
            [task waitUntilExit];
            taskResult = task.terminationStatus;
        }
        @catch (NSException *)
        {
            goto reportError;
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
        if (error)
        {
            SULog(SULogLevelError, @"Couldn't enumerate contents of archive mounted at %@: %@", mountPoint, error);
            goto reportError;
        }

        double itemsCopied = 0;
        double totalItems = [contents count];

		for (NSString *item in contents)
		{
            NSString *fromPath = [mountPoint stringByAppendingPathComponent:item];
            NSString *toPath = [[self.archivePath stringByDeletingLastPathComponent] stringByAppendingPathComponent:item];
            
            // We skip any files in the DMG which are not readable.
            if (![manager isReadableFileAtPath:fromPath]) {
                continue;
            }
            
            itemsCopied += 1.0;
            [notifier notifyProgress:0.5 + itemsCopied/(totalItems*2.0)];
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
            
            @try {
                [task launch];
            } @catch (NSException *exception) {
                SULog(SULogLevelError, @"Failed to unmount %@", mountPoint);
                SULog(SULogLevelError, @"Exception: %@", exception);
            }
        } else {
            SULog(SULogLevelError, @"Can't mount DMG %@", self.archivePath);
        }
    }
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], self.archivePath]; }

@end
