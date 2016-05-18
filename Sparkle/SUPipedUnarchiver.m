//
//  SUPipedUnarchiver.m
//  Sparkle
//
//  Created by Andy Matuschak on 6/16/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUPipedUnarchiver.h"
#import "SULog.h"

#ifdef _APPKITDEFINES_H
#error This is a "core" class and should NOT import AppKit
#endif

@interface SUPipedUnarchiver ()

@property (nonatomic, copy, readonly) NSString *archivePath;
@property (nonatomic, weak, readonly) id <SUUnarchiverDelegate> delegate;

@end

@implementation SUPipedUnarchiver

@synthesize archivePath = _archivePath;
@synthesize delegate = _delegate;

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
        NSArray<NSString *> *value = [extractCommandDictionary objectForKey:currentType];
        assert(value != nil);
        
        if ([currentType length] > [lastPathComponent length]) continue;
        if ([[lastPathComponent substringFromIndex:[lastPathComponent length] - [currentType length]] isEqualToString:currentType]) {
            return value;
        }
    }
    return nil;
}

+ (BOOL)canUnarchivePath:(NSString *)path
{
    return ([self commandAndArgumentsConformingToTypeOfPath:path] != nil);
}

- (instancetype)initWithArchivePath:(NSString *)archivePath delegate:(nullable id <SUUnarchiverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _archivePath = [archivePath copy];
        _delegate = delegate;
    }
    return self;
}

- (void)start
{
    NSArray <NSString *> *commandAndArguments = [[self class] commandAndArgumentsConformingToTypeOfPath:self.archivePath];
    assert(commandAndArguments != nil);
    
    NSString *command = commandAndArguments.firstObject;
    assert(command != nil);
    
    NSArray <NSString *> *arguments = [commandAndArguments subarrayWithRange:NSMakeRange(1, commandAndArguments.count - 1)];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self extractArchivePipingDataToCommand:command arguments:arguments];
    });
}

// This method abstracts the types that use a command line tool piping data from stdin.
- (void)extractArchivePipingDataToCommand:(NSString *)command arguments:(NSArray*)args
{
    // *** GETS CALLED ON NON-MAIN THREAD!!!
	@autoreleasepool {

        NSString *destination = [self.archivePath stringByDeletingLastPathComponent];
        
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
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([self.delegate respondsToSelector:@selector(unarchiverExtractedProgress:)]) {
                        [self.delegate unarchiverExtractedProgress:(double)bytesRead / (double)expectedLength];
                    }
                });
            }
            while(bytesRead < expectedLength);
            
            [archiveOutput closeFile];

            [task waitUntilExit];
            
            if ([task terminationStatus] == 0) {
                if (bytesRead == expectedLength) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.delegate unarchiverDidFinish];
                    });
                    return;
                } else {
                    SULog(@"Extraction failed, command '%@' got only %ld of %ld bytes", command, (long)bytesRead, (long)expectedLength);
                }
            } else {
                SULog(@"Extraction failed, command '%@' returned %d", command, [task terminationStatus]);
            }
        } else {
            SULog(@"Extraction failed, archive '%@' is empty", self.archivePath);
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate unarchiverDidFail];
        });
    }
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], self.archivePath]; }

@end
