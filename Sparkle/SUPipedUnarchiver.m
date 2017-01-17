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

+ (BOOL)unsafeIfArchiveIsNotValidated
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
        NSError *error = nil;
        NSString *destination = [self.archivePath stringByDeletingLastPathComponent];
        
        SULog(SULogLevelDefault, @"Extracting using '%@' '%@' < '%@' '%@'", command, [args componentsJoinedByString:@"' '"], self.archivePath, destination);
        
        // Get the file size.
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.archivePath error:nil];
        NSUInteger expectedLength = [[attributes objectForKey:NSFileSize] unsignedIntegerValue];
        if (expectedLength > 0) {
            NSFileHandle *archiveInput = [NSFileHandle fileHandleForReadingAtPath:self.archivePath];
            
            NSPipe *pipe = [NSPipe pipe];
            NSFileHandle *archiveOutput = [pipe fileHandleForWriting];
            
            NSTask *task = [[NSTask alloc] init];
            [task setStandardInput:[pipe fileHandleForReading]];
            [task setStandardError:[NSFileHandle fileHandleWithStandardError]];
            [task setStandardOutput:[NSFileHandle fileHandleWithStandardOutput]];
            [task setLaunchPath:command];
            [task setArguments:[args arrayByAddingObject:destination]];
            [task launch];
            
            NSUInteger bytesRead = 0;
            do {
                NSData *data = [archiveInput readDataOfLength:256*1024];
                NSUInteger len = [data length];
                if (!len) {
                    break;
                }
                bytesRead += len;
                [archiveOutput writeData:data];
                [notifier notifyProgress:(double)bytesRead / (double)expectedLength];
            }
            while(bytesRead < expectedLength);
            
            [archiveOutput closeFile];
            
            [task waitUntilExit];
            
            if ([task terminationStatus] == 0) {
                if (bytesRead == expectedLength) {
                    [notifier notifySuccess];
                    return;
                } else {
                    error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Extraction failed, command '%@' got only %ld of %ld bytes", command, (long)bytesRead, (long)expectedLength]}];

                }
            } else {
                error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Extraction failed, command '%@' returned %d", command, [task terminationStatus]]}];
            }
        } else {
            error = [NSError errorWithDomain:SUSparkleErrorDomain code:SUUnarchivingError userInfo:@{ NSLocalizedDescriptionKey:[NSString stringWithFormat:@"Extraction failed, archive '%@' is empty", self.archivePath]}];
        }
        [notifier notifyFailureWithError:error];
    }
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], self.archivePath]; }

@end
