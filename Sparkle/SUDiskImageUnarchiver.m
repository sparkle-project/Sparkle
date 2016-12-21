//
//  SUDiskImageUnarchiver.m
//  Sparkle
//
//  Created by Andy Matuschak on 6/16/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUDiskImageUnarchiver.h"
#import "SULog.h"

@interface SUDiskImageUnarchiver ()

@property (nonatomic, copy, readonly) NSString *archivePath;
@property (nullable, nonatomic, copy, readonly) NSString *decryptionPassword;
@property (nonatomic, weak, readonly) id <SUUnarchiverDelegate> delegate;

@end

@implementation SUDiskImageUnarchiver

@synthesize archivePath = _archivePath;
@synthesize decryptionPassword = _decryptionPassword;
@synthesize delegate = _delegate;

+ (BOOL)canUnarchivePath:(NSString *)path
{
    return [[path pathExtension] isEqualToString:@"dmg"];
}

+ (BOOL)unsafeIfArchiveIsNotValidated
{
    return NO;
}

- (instancetype)initWithArchivePath:(NSString *)archivePath decryptionPassword:(nullable NSString *)decryptionPassword delegate:(nullable id <SUUnarchiverDelegate>)delegate
{
    self = [super init];
    if (self != nil) {
        _archivePath = [archivePath copy];
        _decryptionPassword = [decryptionPassword copy];
        _delegate = delegate;
    }
    return self;
}

// Called on a non-main thread.
- (void)extractDMG
{
    @autoreleasepool {
        BOOL mountedSuccessfully = NO;
        
        // get a unique mount point path
        NSString *mountPoint = nil;
        NSFileManager *manager;
        NSError *error;
        NSArray *contents;
        // We have to declare these before a goto to prevent an error under ARC.
        // No, we cannot have them in the dispatch_async calls, as the goto "jump enters
        // lifetime of block which strongly captures a variable"
        dispatch_block_t delegateFailure = ^{
            [self.delegate unarchiverDidFail];
        };
        dispatch_block_t delegateSuccess = ^{
            [self.delegate unarchiverDidFinish];
        };
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
        
        if (taskResult != 0)
        {
            NSString *resultStr = output ? [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding] : nil;
            SULog(@"hdiutil failed with code: %ld data: <<%@>>", (long)taskResult, resultStr);
            goto reportError;
        }
        mountedSuccessfully = YES;
        
        // Now that we've mounted it, we need to copy out its contents.
        manager = [[NSFileManager alloc] init];
        contents = [manager contentsOfDirectoryAtPath:mountPoint error:&error];
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
        
        dispatch_async(dispatch_get_main_queue(), delegateSuccess);
        goto finally;
        
    reportError:
        dispatch_async(dispatch_get_main_queue(), delegateFailure);
        
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
                SULog(@"Failed to unmount %@", mountPoint);
                SULog(@"Exception: %@", exception);
            }
        } else {
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

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], self.archivePath]; }

@end
