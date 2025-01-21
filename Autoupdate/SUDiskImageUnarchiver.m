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
#import "SUErrors.h"


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

- (BOOL)needsVerifyBeforeExtractionKey
{
    return NO;
}

- (void)unarchiveWithCompletionBlock:(void (^)(NSError * _Nullable))completionBlock progressBlock:(void (^ _Nullable)(double))progressBlock waitForCleanup:(BOOL)waitForCleanup
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SUUnarchiverNotifier *notifier = [[SUUnarchiverNotifier alloc] initWithCompletionBlock:completionBlock progressBlock:progressBlock];
        [self extractDMGWithNotifier:notifier waitForCleanup:waitForCleanup];
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
- (void)extractDMGWithNotifier:(SUUnarchiverNotifier *)notifier waitForCleanup:(BOOL)waitForCleanup SPU_OBJC_DIRECT
{
	@autoreleasepool {
        BOOL mountedSuccessfully = NO;
        
        // get a unique mount point path
        NSString *mountPoint = nil;
        NSFileManager *manager;
        NSError *error = nil;
        NSArray *contents = nil;
        do {
            NSString *uuidString = [[NSUUID UUID] UUIDString];
            mountPoint = [@"/Volumes" stringByAppendingPathComponent:uuidString];
        }
        // Note: this check does not follow symbolic links, which is what we want
        while ([[NSURL fileURLWithPath:mountPoint] checkResourceIsReachableAndReturnError:NULL]);
        
        NSMutableData *inputData = [NSMutableData data];
        
        // Prepare stdin data for passwords and license agreements
        {
            // If no password is supplied, we will still be asked a password.
            // In that case we respond with an empty password.
            NSData *decryptionPasswordData = [_decryptionPassword dataUsingEncoding:NSUTF8StringEncoding];
            if (decryptionPasswordData != nil) {
                [inputData appendData:decryptionPasswordData];
            }
            
            // From the hdiutil docs:
            // read a null-terminated passphrase from standard input
            //
            // Add the null terminator
            [inputData appendBytes:"\0" length:1];
            
            // Append prompt data for license agreements
            [inputData appendBytes:"yes\n" length:4];
        }
        
        // Finder doesn't verify disk images anymore beyond the code signing signature (if available)
        // Opt out of the old CRC checksum checks
        // Also always pass -stdinpass so we gracefully handle password protected disk images even if we aren't expecting them
        NSArray *arguments = @[@"attach", _archivePath, @"-mountpoint", mountPoint, @"-noverify", @"-nobrowse", @"-noautoopen", @"-stdinpass"];
        
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
            
            if (@available(macOS 10.15, *)) {
                if (![inputPipe.fileHandleForWriting writeData:inputData error:&error]) {
                    goto reportError;
                }
            }
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_15
            else
            {
                @try {
                    [inputPipe.fileHandleForWriting writeData:inputData];
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
        
        if (taskResult != 0) {
            NSString *resultStr = output ? [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] : nil;
            SULog(SULogLevelError, @"hdiutil failed with code: %ld data: <<%@>>", (long)taskResult, resultStr);
            
            error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Extraction failed due to hdiutil returning %ld status: %@", (long)taskResult, resultStr]}];
            
            goto reportError;
        }
        
        mountedSuccessfully = YES;
        
        // Mounting can take some time, so increment progress
        _currentExtractionProgress = 0.1;
        [notifier notifyProgress:_currentExtractionProgress];
        
        // Now that we've mounted it, we need to copy out its contents.
        manager = [[NSFileManager alloc] init];
        contents = [manager contentsOfDirectoryAtPath:mountPoint error:&error];
        if (contents == nil) {
            SULog(SULogLevelError, @"Couldn't enumerate contents of archive mounted at %@: %@", mountPoint, error);
            goto reportError;
        }
        
        // Sparkle can support installing pkg files, app bundles, and other bundle types for plug-ins
        // We must not filter any of those out
        for (NSString *item in contents) {
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
                // Skip directory types that aren't bundles or regular directories
                if ([pathExtension isEqualToString:@"rtfd"]) {
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
        
        _fileProgressIncrement = (0.99 - _currentExtractionProgress) / totalFileExtractionCount;
        _notifier = notifier;
        
        // Copy all items we want to extract and notify of progress
        manager.delegate = self;
        for (NSString *item in itemsToExtract) {
            NSURL *fromURL = [mountPointURL URLByAppendingPathComponent:item];
            NSURL *toURL = [extractionDirectoryURL URLByAppendingPathComponent:item];
            
            if (![manager copyItemAtURL:fromURL toURL:toURL error:&error]) {
                SULog(SULogLevelError, @"Failed to copy '%@' to '%@' with error: %@", fromURL.path, toURL.path, error);
                goto reportError;
            }
        }
        
        [notifier notifyProgress:1.0];
        
        BOOL success = YES;
        goto finally;
        
    reportError:
        success = NO;

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
            } else if (waitForCleanup) {
                [task waitUntilExit];
            }
        } else {
            SULog(SULogLevelError, @"Can't mount DMG %@", _archivePath);
        }
        
        if (success) {
            [notifier notifySuccess];
        } else {
            [notifier notifyFailureWithError:error];
        }
    }
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], _archivePath]; }

@end
