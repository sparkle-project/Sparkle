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

@interface SUPipedUnarchiver ()

@property (nonatomic, copy, readonly) NSString *archivePath;

@end

@implementation SUPipedUnarchiver

@synthesize archivePath = _archivePath;

+ (nullable NSArray <NSString *> *)commandAndArgumentsConformingToTypeOfPath:(NSString *)path
{
    NSArray <NSString *> *extractTGZ = @[@"/usr/bin/tar", @"-zxC"];
    NSArray <NSString *> *extractTBZ = @[@"/usr/bin/tar", @"-jxC"];
    NSArray <NSString *> *extractTXZ = extractTGZ;
    
    NSDictionary <NSString *, NSArray<NSString *> *> *extractCommandDictionary =
    @{
      @".zip" : @[@"/usr/bin/ditto", @"-x",@"-k",@"-"],
      @".tar" : @[@"/usr/bin/tar", @"-xC"],
      @".tar.gz" : extractTGZ,
      @".tgz" : extractTGZ,
      @".tar.bz2" : extractTBZ,
      @".tbz" : extractTBZ,
      @".tar.xz" : extractTXZ,
      @".txz" : extractTXZ,
      @".tar.lzma" : extractTXZ
    };
    
    NSString *lastPathComponent = [path lastPathComponent];
    for (NSString *currentType in extractCommandDictionary)
    {
        if ([lastPathComponent hasSuffix:currentType]) {
            return [extractCommandDictionary objectForKey:currentType];
        }
    }
    return nil;
}

+ (BOOL)canUnarchivePath:(NSString *)path
{
    return ([self commandAndArgumentsConformingToTypeOfPath:path] != nil);
}

+ (BOOL)mustValidateBeforeExtraction
{
    return NO;
}

- (instancetype)initWithArchivePath:(NSString *)archivePath
{
    self = [super init];
    if (self != nil) {
        _archivePath = [archivePath copy];
    }
    return self;
}

- (void)unarchiveWithCompletionBlock:(void (^)(NSError * _Nullable))completionBlock progressBlock:(void (^ _Nullable)(double))progressBlock
{
    NSArray <NSString *> *commandAndArguments = [[self class] commandAndArgumentsConformingToTypeOfPath:self.archivePath];
    assert(commandAndArguments != nil);
    
    NSString *command = commandAndArguments.firstObject;
    assert(command != nil);
    
    NSArray <NSString *> *arguments = [commandAndArguments subarrayWithRange:NSMakeRange(1, commandAndArguments.count - 1)];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        SUUnarchiverNotifier *notifier = [[SUUnarchiverNotifier alloc] initWithCompletionBlock:completionBlock progressBlock:progressBlock];
        [self extractArchivePipingDataToCommand:command arguments:arguments notifier:notifier];
    });
}

// This method abstracts the types that use a command line tool piping data from stdin.
- (void)extractArchivePipingDataToCommand:(NSString *)command arguments:(NSArray*)args notifier:(SUUnarchiverNotifier *)notifier
{
    // *** GETS CALLED ON NON-MAIN THREAD!!!
	@autoreleasepool {
        NSString *destination = [self.archivePath stringByDeletingLastPathComponent];
        
        SULog(SULogLevelDefault, @"Extracting using '%@' '%@' < '%@' '%@'", command, [args componentsJoinedByString:@"' '"], self.archivePath, destination);
        
        // Get the file size.
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.archivePath error:nil];
        NSUInteger expectedLength = [(NSNumber *)[attributes objectForKey:NSFileSize] unsignedIntegerValue];
        
        if (expectedLength == 0) {
            NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Extraction failed, archive '%@' is empty", self.archivePath]}];
            
            [notifier notifyFailureWithError:error];
            return;
        }
        
        NSFileHandle *archiveInput = [NSFileHandle fileHandleForReadingAtPath:self.archivePath];
        
        NSPipe *pipe = [NSPipe pipe];
        NSTask *task = [[NSTask alloc] init];
        [task setStandardInput:pipe];
        [task setStandardError:[NSFileHandle fileHandleWithStandardError]];
        [task setStandardOutput:[NSFileHandle fileHandleWithStandardOutput]];
        [task setLaunchPath:command];
        [task setArguments:[args arrayByAddingObject:destination]];
        
        NSError *launchError = nil;
        if (@available(macOS 10.13, *)) {
            if (![task launchAndReturnError:&launchError]) {
                [notifier notifyFailureWithError:launchError];
                return;
            }
        } else {
            @try {
                [task launch];
            } @catch (NSException *e) {
                NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Extraction failed, -[NSTask launch] threw exception '%@'", e.description]}];
                [notifier notifyFailureWithError:error];
                return;
            }
        }
        
        NSFileHandle *archiveOutput = [pipe fileHandleForWriting];
        NSUInteger bytesWritten = 0;
        
        BOOL hasIOErrorMethods;
        if (@available(macOS 10.15, *)) {
            hasIOErrorMethods = YES;
        } else {
            hasIOErrorMethods = NO;
        }
        
        do {
            NSData *data;
            if (hasIOErrorMethods) {
                NSError *readError = nil;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
                data = [archiveInput readDataUpToLength:256*1024 error:&readError];
#pragma clang diagnostic pop
                if (data == nil) {
                    SULog(SULogLevelError, @"Failed to read data from archive with error %@", readError);
                }
            } else {
                @try {
                    data = [archiveInput readDataOfLength:256*1024];
                } @catch (NSException *exception) {
                    SULog(SULogLevelError, @"Failed to read data from archive with exception reason %@", exception.reason);
                    data = nil;
                }
            }
            
            NSUInteger len = [data length];
            if (len == 0) {
                break;
            }
            
            NSError *writeError = nil;
            if (hasIOErrorMethods) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
                if (![archiveOutput writeData:data error:&writeError]) {
#pragma clang diagnostic pop
                    SULog(SULogLevelError, @"Failed to write data to pipe with error %@", writeError);
                    break;
                }
            } else {
                @try {
                    [archiveOutput writeData:data];
                } @catch (NSException *exception) {
                    SULog(SULogLevelError, @"Failed to write data to pipe with exception reason %@", exception.reason);
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
        } else {
            [archiveOutput closeFile];
        }
        
        if (@available(macOS 10.15, *)) {
            NSError *archiveInputCloseError = nil;
            if (![archiveInput closeAndReturnError:&archiveInputCloseError]) {
                SULog(SULogLevelError, @"Failed to close archive input with error %@", archiveInputCloseError);
            }
        } else {
            [archiveInput closeFile];
        }
        
        [task waitUntilExit];
        
        if ([task terminationStatus] != 0) {
            NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Extraction failed, command '%@' returned %d", command, [task terminationStatus]]}];
            
            [notifier notifyFailureWithError:error];
            return;
        }
        
        if (bytesWritten != expectedLength) {
            NSError *error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Extraction failed, command '%@' got only %ld of %ld bytes", command, (long)bytesWritten, (long)expectedLength]}];
            
            [notifier notifyFailureWithError:error];
            return;
        }
        
        [notifier notifySuccess];
    }
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], self.archivePath]; }

@end
