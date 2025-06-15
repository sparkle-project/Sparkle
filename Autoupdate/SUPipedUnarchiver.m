//
//  SUPipedUnarchiver.m
//  Sparkle
//
//  Created by Andy Matuschak on 6/16/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPipedUnarchiver.h"
#import "SUUnarchiverNotifier.h"
#import "SULog.h"
#import "SUErrors.h"


#include "AppKitPrevention.h"

@implementation SUPipedUnarchiver
{
    NSString *_archivePath;
    NSString *_extractionDirectory;
}

// pipingData == NO is only supported for zip archives
static NSArray<NSString *> * _Nullable argumentsConformingToTypeOfPath(NSString *path, BOOL pipingData, NSString * __autoreleasing *outCommand)
{
    NSArray <NSString *> *extractTGZ = @[@"/usr/bin/tar", @"-zxC"];
    NSArray <NSString *> *extractTBZ = @[@"/usr/bin/tar", @"-jxC"];
    NSArray <NSString *> *extractTXZ = extractTGZ;
    
    // Note: keep this list in sync with generate_appcast's unarchiveUpdates()
    NSMutableDictionary <NSString *, NSArray<NSString *> *> *extractCommandDictionary =
    [@{
      @".zip" : (pipingData ? @[@"/usr/bin/ditto", @"-x", @"-k", @"-"] : @[@"/usr/bin/ditto", @"-x", @"-k", path]),
      @".tar" : @[@"/usr/bin/tar", @"-xC"],
      @".tar.gz" : extractTGZ,
      @".tgz" : extractTGZ,
      @".tar.bz2" : extractTBZ,
      @".tbz" : extractTBZ,
      @".tar.xz" : extractTXZ,
      @".txz" : extractTXZ,
      @".tar.lzma" : extractTXZ,
    } mutableCopy];
    
    // At least the latest versions of 10.15 understand how to extract aar files
    // Versions before 10.15 do not understand extracting newly created aar files
    // Note encrypted aea files are supported in macOS 12 onwards, if we ever want to support those one day
    if (@available(macOS 10.15.7, *)) {
        NSString *appleArchiveCommand;
        if (@available(macOS 11, *)) {
            appleArchiveCommand = @"/usr/bin/aa";
        } else {
            // In 10.15 the utility was named yaa, which was later renamed to aar
            appleArchiveCommand = @"/usr/bin/yaa";
        }
        
        NSArray <NSString *> *extractAppleArchive = @[appleArchiveCommand, @"extract", @"-d"];
        
        [extractCommandDictionary addEntriesFromDictionary:@{
            @".aar" : extractAppleArchive,
            @".yaa" : extractAppleArchive,
        }];
    }
    
    NSString *lastPathComponent = [path lastPathComponent];
    for (NSString *currentType in extractCommandDictionary)
    {
        if ([lastPathComponent hasSuffix:currentType]) {
            NSArray<NSString *> *commandAndArguments = [extractCommandDictionary objectForKey:currentType];
            if (outCommand != NULL) {
                *outCommand = commandAndArguments.firstObject;
            }
            
            return [commandAndArguments subarrayWithRange:NSMakeRange(1, commandAndArguments.count - 1)];
        }
    }
    return nil;
}

+ (BOOL)canUnarchivePath:(NSString *)path
{
    return argumentsConformingToTypeOfPath(path, YES, NULL) != nil;
}

+ (BOOL)mustValidateBeforeExtraction
{
    return NO;
}

- (instancetype)initWithArchivePath:(NSString *)archivePath extractionDirectory:(NSString *)extractionDirectory
{
    self = [super init];
    if (self != nil) {
        _archivePath = [archivePath copy];
        _extractionDirectory = [extractionDirectory copy];
    }
    return self;
}

- (BOOL)needsVerifyBeforeExtractionKey
{
    return ([_archivePath hasSuffix:@".aar"] || [_archivePath hasSuffix:@".yaa"]);
}

- (void)unarchiveWithCompletionBlock:(void (^)(NSError * _Nullable))completionBlock progressBlock:(void (^ _Nullable)(double))progressBlock waitForCleanup:(BOOL)__unused waitForCleanup
{
    NSString *command = nil;
    NSArray<NSString *> *arguments = argumentsConformingToTypeOfPath(_archivePath, YES, &command);
    assert(arguments != nil);
    assert(command != nil);
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            SUUnarchiverNotifier *notifier = [[SUUnarchiverNotifier alloc] initWithCompletionBlock:completionBlock progressBlock:progressBlock];
            NSError *extractError = nil;
            if ([self extractArchivePipingData:YES command:command arguments:arguments notifier:notifier error:&extractError]) {
                [notifier notifySuccess];
            } else {
                // If we fail due to an IO PIPE write failure for zip files,
                // we may re-attempt extracting the archive without piping archive data
                // (and without fine grained progress reporting).
                // This is to workaround a bug in ditto which causes extraction to fail when piping data for
                // some types of constructed zip files.
                // Note this bug is fixed on macOS 15+, so this workaround is not needed there.
                // https://github.com/sparkle-project/Sparkle/issues/2544
                BOOL useNonPipingWorkaround;
                if (@available(macOS 15, *)) {
                    useNonPipingWorkaround = NO;
                } else {
                    NSError *underlyingError = extractError.userInfo[NSUnderlyingErrorKey];
                    
                    useNonPipingWorkaround = [self->_archivePath.pathExtension isEqualToString:@"zip"] && ([extractError.domain isEqualToString:SUSparkleErrorDomain] && extractError.code == SUUnarchivingError && [underlyingError.domain isEqualToString:NSPOSIXErrorDomain] && underlyingError.code == EPIPE);
                }
                
                if (!useNonPipingWorkaround) {
                    [notifier notifyFailureWithError:extractError];
                } else {
                    // Re-create the extraction directory, then try extracting without piping
                    
                    NSFileManager *fileManager = [NSFileManager defaultManager];
                    
                    NSURL *extractionDirectoryURL = [NSURL fileURLWithPath:self->_extractionDirectory isDirectory:YES];
                    
                    NSError *removeError = nil;
                    if (![fileManager removeItemAtURL:extractionDirectoryURL error:&removeError]) {
                        SULog(SULogLevelError, @"Failed to remove extraction directory path for non-piping workaround with error: %@", removeError);
                        
                        [notifier notifyFailureWithError:extractError];
                    } else {
                        NSError *createError = nil;
                        if (![fileManager createDirectoryAtPath:self->_extractionDirectory withIntermediateDirectories:NO attributes:nil error:&createError]) {
                            SULog(SULogLevelError, @"Failed to create new extraction directory path for non-piping workaround with error: %@", createError);
                            
                            [notifier notifyFailureWithError:extractError];
                        } else {
                            // The ditto command will be the same so no need to fetch it again
                            NSArray<NSString *> *nonPipingArguments = argumentsConformingToTypeOfPath(self->_archivePath, NO, NULL);
                            assert(nonPipingArguments != nil);
                            
                            NSError *nonPipingExtractError = nil;
                            if ([self extractArchivePipingData:NO command:command arguments:nonPipingArguments notifier:notifier error:&nonPipingExtractError]) {
                                [notifier notifySuccess];
                            } else {
                                [notifier notifyFailureWithError:nonPipingExtractError];
                            }
                        }
                    }
                }
            }
        }
    });
}

// This method abstracts the types that use a command line tool piping data from stdin.
- (BOOL)extractArchivePipingData:(BOOL)pipingData command:(NSString *)command arguments:(NSArray*)args notifier:(SUUnarchiverNotifier *)notifier error:(NSError * __autoreleasing *)outError SPU_OBJC_DIRECT
{
    // *** GETS CALLED ON NON-MAIN THREAD!!!
    NSString *destination = _extractionDirectory;
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (pipingData) {
        SULog(SULogLevelDefault, @"Extracting using '%@' '%@' < '%@' '%@'", command, [args componentsJoinedByString:@"' '"], _archivePath, destination);
    } else {
        SULog(SULogLevelDefault, @"Extracting using '%@' '%@' '%@'", command, [args componentsJoinedByString:@"' '"], destination);
    }
    
    // Get expected file size for piping the archive
    NSUInteger expectedLength;
    if (pipingData) {
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:_archivePath error:nil];
        expectedLength = [(NSNumber *)[attributes objectForKey:NSFileSize] unsignedIntegerValue];
        
        if (expectedLength == 0) {
            NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Extraction failed, archive '%@' is empty", _archivePath]}];
            
            if (outError != NULL) {
                *outError = error;
            }
            
            return NO;
        }
    } else {
        expectedLength = 0;
    }
    
    NSTask *task = [[NSTask alloc] init];
    
    NSPipe *pipe;
    if (pipingData) {
        pipe = [NSPipe pipe];
        [task setStandardInput:pipe];
    } else {
        pipe = nil;
    }
    
    [task setStandardError:[NSFileHandle fileHandleWithStandardError]];
    [task setStandardOutput:[NSFileHandle fileHandleWithStandardOutput]];
    [task setLaunchPath:command];
    [task setArguments:[args arrayByAddingObject:destination]];
    
    NSError *launchError = nil;
    if (![task launchAndReturnError:&launchError]) {
        if (outError != NULL) {
            *outError = launchError;
        }
        return NO;
    }
    
    NSError *underlyingOutError = nil;
    NSUInteger bytesWritten = 0;
    
    if (pipingData) {
        NSFileHandle *archiveInput = [NSFileHandle fileHandleForReadingAtPath:_archivePath];
        
        NSFileHandle *archiveOutput = [pipe fileHandleForWriting];
        
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_15
        BOOL hasIOErrorMethods;
        if (@available(macOS 10.15, *)) {
            hasIOErrorMethods = YES;
        } else {
            hasIOErrorMethods = NO;
        }
#endif
        
        do {
            NSData *data;
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_15
            if (!hasIOErrorMethods) {
                @try {
                    data = [archiveInput readDataOfLength:256*1024];
                } @catch (NSException *exception) {
                    SULog(SULogLevelError, @"Failed to read data from archive with exception reason %@", exception.reason);
                    data = nil;
                }
            }
            else
#endif
            {
                NSError *readError = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
                data = [archiveInput readDataUpToLength:256*1024 error:&readError];
#pragma clang diagnostic pop
                if (data == nil) {
                    SULog(SULogLevelError, @"Failed to read data from archive with error %@", readError);
                    underlyingOutError = readError;
                }
            }
            
            NSUInteger len = [data length];
            if (len == 0) {
                break;
            }
            
            NSError *writeError = nil;
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_15
            if (!hasIOErrorMethods) {
                @try {
                    [archiveOutput writeData:data];
                } @catch (NSException *exception) {
                    SULog(SULogLevelError, @"Failed to write data to pipe with exception reason %@", exception.reason);
                    
                    if ([exception.name isEqualToString:NSFileHandleOperationException]) {
                        NSError *underlyingFileHandleError = exception.userInfo[@"NSFileHandleOperationExceptionUnderlyingError"];
                        NSError *underlyingPOSIXError = underlyingFileHandleError.userInfo[NSUnderlyingErrorKey];
                        
                        underlyingOutError = underlyingPOSIXError;
                    }
                    
                    break;
                }
            }
            else
#endif
            {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
                if (![archiveOutput writeData:data error:&writeError]) {
#pragma clang diagnostic pop
                    SULog(SULogLevelError, @"Failed to write data to pipe with error %@", writeError);
                    
                    NSError *underlyingPOSIXError = writeError.userInfo[NSUnderlyingErrorKey];
                    
                    underlyingOutError = underlyingPOSIXError;
                    break;
                }
            }
            
            bytesWritten += len;
            
            [notifier notifyProgress:(double)bytesWritten / (double)expectedLength];
        }
        while(bytesWritten < expectedLength);
        
        if (@available(macOS 10.15, *)) {
            NSError *archiveOutputCloseError = nil;
            if (![archiveOutput closeAndReturnError:&archiveOutputCloseError]) {
                SULog(SULogLevelError, @"Failed to close pipe with error %@", archiveOutputCloseError);
            }
        }
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_15
        else
        {
            [archiveOutput closeFile];
        }
#endif
        
        if (@available(macOS 10.15, *)) {
            NSError *archiveInputCloseError = nil;
            if (![archiveInput closeAndReturnError:&archiveInputCloseError]) {
                SULog(SULogLevelError, @"Failed to close archive input with error %@", archiveInputCloseError);
            }
        }
#if MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_15
        else
        {
            [archiveInput closeFile];
        }
#endif
    }
    
    [task waitUntilExit];
    
    if ([task terminationStatus] != 0) {
        NSMutableDictionary *userInfo = [@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Extraction failed, command '%@' returned %d", command, [task terminationStatus]]} mutableCopy];
        
        if (underlyingOutError != nil) {
            userInfo[NSUnderlyingErrorKey] = underlyingOutError;
        }
        
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:[userInfo copy]];
        
        if (outError != NULL) {
            *outError = error;
        }
        
        return NO;
    }
    
    if (!pipingData) {
        [notifier notifyProgress:1.0];
    } else if (bytesWritten != expectedLength) {
        // Don't set underlying error in this case
        // This may fail due to a write PIPE error but we don't currently support extracting archives that have
        // extraneous data leftover because these may be corrupt.
        // We don't want to later workaround extraction by not piping the data.
        NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Extraction failed, command '%@' got only %ld of %ld bytes", command, (long)bytesWritten, (long)expectedLength]}];
        
        if (outError != NULL) {
            *outError = error;
        }
        return NO;
    }
    
    return YES;
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], _archivePath]; }

@end
