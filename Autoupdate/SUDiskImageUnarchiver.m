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

@interface SUDiskImageUnarchiver () <NSFileManagerDelegate>
@end

@implementation SUDiskImageUnarchiver
{
    NSString *_archivePath;
    NSString *_decryptionPassword;
    NSString *_extractionDirectory;
    
    SUUnarchiverNotifier *_notifier;
    double _currentExtractionProgress;
    double _fileProgressIncrement;
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

static NSUInteger fileCountForDirectory(NSFileManager *fileManager, NSString *itemPath)
{
    NSUInteger fileCount = 0;
    NSDirectoryEnumerator *dirEnum = [fileManager enumeratorAtPath:itemPath];
    for (NSString * __unused currentFile in dirEnum) {
        fileCount++;
    }
    
    return fileCount;
}

- (BOOL)fileManager:(NSFileManager *)fileManager shouldCopyItemAtURL:(NSURL *)srcURL toURL:(NSURL *)dstURL
{
    _currentExtractionProgress += _fileProgressIncrement;
    [_notifier notifyProgress:_currentExtractionProgress];
    
    return YES;
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
        
        // Finder doesn't verify disk images anymore beyond the code signing signature (if available)
        // Opt out of the old CRC checksum checks
        NSMutableArray *arguments = [@[@"attach", _archivePath, @"-mountpoint", mountPoint, @"-noverify", @"-nobrowse", @"-noautoopen"] mutableCopy];
        
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
        
        NSURL *mountPointURL = [NSURL fileURLWithPath:mountPoint isDirectory:YES];
        NSURL *extractionDirectoryURL = [NSURL fileURLWithPath:_extractionDirectory isDirectory:YES];
        NSMutableArray<NSString *> *itemsToExtract = [NSMutableArray array];
        NSUInteger totalFileExtractionCount = 0;
        
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
            
            [notifier notifyProgress:0.1];
            
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
        
        [notifier notifyProgress:0.2];

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
        
        // Sparkle can support installing pkg files, app bundles, and other bundle types for plug-ins
        // We must not filter any of those out
		for (NSString *item in contents)
		{
            NSURL *fromPathURL = [mountPointURL URLByAppendingPathComponent:item];
            
            NSString *lastPathComponent = fromPathURL.lastPathComponent;
            
            // Ignore hidden files
            if ([lastPathComponent hasPrefix:@"."]) {
                continue;
            }
            
            // Ignore aliases
            NSNumber *aliasFlag = nil;
            if ([fromPathURL getResourceValue:&aliasFlag forKey:NSURLIsAliasFileKey error:NULL] && aliasFlag.boolValue) {
                continue;
            }
            
            // Ignore symbolic links
            NSNumber *symbolicFlag = nil;
            if ([fromPathURL getResourceValue:&symbolicFlag forKey:NSURLIsSymbolicLinkKey error:NULL] && symbolicFlag.boolValue) {
                continue;
            }
            
            // Ensure file is readable
            NSNumber *isReadableFlag = nil;
            if ([fromPathURL getResourceValue:&isReadableFlag forKey:NSURLIsReadableKey error:NULL] && !isReadableFlag.boolValue) {
                continue;
            }
            
            NSNumber *isDirectoryFlag = nil;
            if (![fromPathURL getResourceValue:&isDirectoryFlag forKey:NSURLIsDirectoryKey error:NULL]) {
                continue;
            }
            
            BOOL isDirectory = isDirectoryFlag.boolValue;
            NSString *pathExtension = fromPathURL.pathExtension;
            
            if (isDirectory) {
                // Skip directory types that aren't bundles
                if ([pathExtension isEqualTo:@"rtfd"]) {
                    continue;
                }
            } else {
                // The only non-directory files we care about are (m)pkg files
                if (![pathExtension isEqualToString:@"pkg"] && ![pathExtension isEqualToString:@"mpkg"]) {
                    continue;
                }
            }
            
            if (isDirectory) {
                totalFileExtractionCount += fileCountForDirectory(manager, fromPathURL.path);
            } else {
                totalFileExtractionCount++;
            }
            
            [itemsToExtract addObject:item];
        }
        
        [notifier notifyProgress:0.3];
        _currentExtractionProgress = 0.3;
        
        _fileProgressIncrement = 0.65 / totalFileExtractionCount;
        _notifier = notifier;
        
        // Copy all items we want to extract and notify of progress
        manager.delegate = self;
        for (NSString *item in itemsToExtract) {
            NSURL *fromURL = [mountPointURL URLByAppendingPathComponent:item];
            NSURL *toURL = [extractionDirectoryURL URLByAppendingPathComponent:item];
            
            if (![manager copyItemAtURL:fromURL toURL:toURL error:&error]) {
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
            
            [notifier notifyProgress:1.0];
        } else {
            SULog(SULogLevelError, @"Can't mount DMG %@", _archivePath);
        }
    }
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], _archivePath]; }

@end

#endif
