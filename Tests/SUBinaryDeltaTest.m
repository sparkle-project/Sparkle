//
//  SUBinaryDeltaTest.m
//  Sparkle
//
//  Created by Jake Petroules on 2014-08-22.
//  Copyright (c) 2014 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>
#import "SUBinaryDeltaCommon.h"
#import "SUBinaryDeltaCreate.h"
#import "SUBinaryDeltaApply.h"

@interface SUBinaryDeltaTest : XCTestCase

@end

@implementation SUBinaryDeltaTest

- (void)testTemporaryDirectory
{
    NSString *tmp1 = temporaryDirectory(@"Sparkle");
    NSString *tmp2 = temporaryDirectory(@"Sparkle");
    NSLog(@"Temporary directories: %@, %@", tmp1, tmp2);
    XCTAssertNotEqualObjects(tmp1, tmp2);
    XCTAssert(YES, @"Pass");
}

- (void)testTemporaryFile
{
    NSString *tmp1 = temporaryFilename(@"Sparkle");
    NSString *tmp2 = temporaryFilename(@"Sparkle");
    NSLog(@"Temporary files: %@, %@", tmp1, tmp2);
    XCTAssertNotEqualObjects(tmp1, tmp2);
    XCTAssert(YES, @"Pass");
}

- (void)createAndApplyPatchWithHandler:(void (^)(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory))handler
{
    NSString *sourceDirectory = temporaryDirectory(@"Sparkle_temp1");
    NSString *destinationDirectory = temporaryDirectory(@"Sparkle_temp2");
    
    NSString *diffFile = temporaryFilename(@"Sparkle_diff");
    NSString *patchDirectory = temporaryDirectory(@"Sparkle_patch");
    
    XCTAssertNotNil(sourceDirectory);
    XCTAssertNotNil(destinationDirectory);
    XCTAssertNotNil(diffFile);
    
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    
    handler(fileManager, sourceDirectory, destinationDirectory);
    
    XCTAssertEqual(0, createBinaryDelta(sourceDirectory, destinationDirectory, diffFile));
    XCTAssertEqual(0, applyBinaryDelta(sourceDirectory, patchDirectory, diffFile));
    
    XCTAssertTrue([fileManager removeItemAtPath:sourceDirectory error:nil]);
    XCTAssertTrue([fileManager removeItemAtPath:destinationDirectory error:nil]);
    XCTAssertTrue([fileManager removeItemAtPath:patchDirectory error:nil]);
    XCTAssertTrue([fileManager removeItemAtPath:diffFile error:nil]);
}

- (BOOL)testDirectoryHashEqualityWithSource:(NSString *)source destination:(NSString *)destination
{
    XCTAssertNotNil(source);
    XCTAssertNotNil(destination);
    
    NSString *beforeHash = hashOfTree(source);
    NSString *afterHash = hashOfTree(destination);
    
    XCTAssertNotNil(beforeHash);
    XCTAssertNotNil(afterHash);
    
    return [beforeHash isEqualToString:afterHash];
}

- (void)testEmptyDataDiff
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSData *emptyData = [NSData data];
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([emptyData writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([emptyData writeToFile:destinationFile atomically:YES]);
        
        XCTAssertTrue([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testSmallDataDiff
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[NSData data] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[NSData dataWithBytes:"loltest" length:7] writeToFile:destinationFile atomically:YES]);
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (NSData *)bigData1
{
    const size_t bufferSize = 4096*10;
    uint8_t *buffer = calloc(1, bufferSize);
    XCTAssertTrue(buffer != NULL);
    
    return [NSData dataWithBytesNoCopy:buffer length:bufferSize];
}

- (NSData *)bigData2
{
    const size_t bufferSize = 4096*10;
    uint8_t *buffer = calloc(1, bufferSize);
    XCTAssertTrue(buffer != NULL);
    
    for (size_t bufferIndex = 0; bufferIndex < bufferSize; ++bufferIndex) {
        buffer[bufferIndex] = 1;
    }
    
    return [NSData dataWithBytesNoCopy:buffer length:bufferSize];
}

- (void)testBigDataSameDiff
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];

        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData1] writeToFile:destinationFile atomically:YES]);
        
        XCTAssertTrue([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testBigDataDifferentDiff
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testRegularFileAdded
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile2 = [destinationDirectory stringByAppendingPathComponent:@"B"];
        
        XCTAssertTrue([[NSData data] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[NSData dataWithBytes:"loltest" length:7] writeToFile:destinationFile atomically:YES]);
        XCTAssertTrue([[NSData dataWithBytes:"lol" length:3] writeToFile:destinationFile2 atomically:YES]);
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testDirectoryAdded
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        
        NSString *destinationFile1 = [destinationDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile2 = [destinationDirectory stringByAppendingPathComponent:@"B"];
        NSString *destinationFile3 = [destinationFile2 stringByAppendingPathComponent:@"C"];
        
        XCTAssertTrue([[NSData data] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[NSData dataWithBytes:"loltest" length:7] writeToFile:destinationFile1 atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:destinationFile2 withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTAssertFalse("Failed to create directory");
        }
        
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile3 atomically:YES]);
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testRegularFileRemoved
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *sourceFile2 = [destinationDirectory stringByAppendingPathComponent:@"B"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[NSData data] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[NSData dataWithBytes:"lol" length:3] writeToFile:sourceFile2 atomically:YES]);
        XCTAssertTrue([[NSData dataWithBytes:"loltest" length:7] writeToFile:destinationFile atomically:YES]);
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testDirectoryRemoved
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSString *sourceFile1 = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *sourceFile2 = [sourceDirectory stringByAppendingPathComponent:@"B"];
        NSString *sourceFile3 = [sourceFile2 stringByAppendingPathComponent:@"C"];
        
        XCTAssertTrue([[NSData data] writeToFile:destinationFile atomically:YES]);
        XCTAssertTrue([[NSData dataWithBytes:"loltest" length:7] writeToFile:sourceFile1 atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:sourceFile2 withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTAssertFalse("Failed to create directory");
        }
        
        XCTAssertTrue([[self bigData2] writeToFile:sourceFile3 atomically:YES]);
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testRegularFileMove
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"B"];
        
        NSData *data = [NSData dataWithBytes:"loltest" length:7];
        XCTAssertTrue([data writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile atomically:YES]);
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testCaseSensitiveRegularFileMove
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile1 = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *sourceFile2 = [sourceDirectory stringByAppendingPathComponent:@"b"];
        
        NSString *destinationFile1 = [destinationDirectory stringByAppendingPathComponent:@"a"];
        NSString *destinationFile2 = [destinationDirectory stringByAppendingPathComponent:@"B"];
        
        NSData *data = [NSData dataWithBytes:"loltest" length:7];
        
        XCTAssertTrue([data writeToFile:sourceFile1 atomically:YES]);
        XCTAssertTrue([data writeToFile:sourceFile2 atomically:YES]);
        
        XCTAssertTrue([data writeToFile:destinationFile1 atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile2 atomically:YES]);
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testExecutableFilePermissionChangedWithHashCheck
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSData *data = [NSData dataWithBytes:"loltest" length:7];
        XCTAssertTrue([data writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0755} ofItemAtPath:destinationFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        // This would fail for version 1.0
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testRegularFileToSymlinkChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile1 = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *sourceFile2 = [sourceDirectory stringByAppendingPathComponent:@"B"];
        
        NSString *destinationFile1 = [destinationDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile2 = [destinationDirectory stringByAppendingPathComponent:@"B"];
        
        NSData *data = [NSData dataWithBytes:"A" length:1];
        
        XCTAssertTrue([data writeToFile:sourceFile1 atomically:YES]);
        XCTAssertTrue([data writeToFile:sourceFile2 atomically:YES]);
        
        XCTAssertTrue([data writeToFile:destinationFile1 atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager createSymbolicLinkAtPath:destinationFile2 withDestinationPath:@"A" error:&error]) {
            NSLog(@"Error in creating symlink: %@", error);
            XCTFail(@"Failed to create symlink");
        }
        
        // This would fail with version 1.0
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testSymlinkToRegularFileChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile1 = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *sourceFile2 = [sourceDirectory stringByAppendingPathComponent:@"B"];
        
        NSString *destinationFile1 = [destinationDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile2 = [destinationDirectory stringByAppendingPathComponent:@"B"];
        
        NSData *data = [NSData dataWithBytes:"loltest" length:7];
        
        XCTAssertTrue([data writeToFile:sourceFile1 atomically:YES]);
        
        XCTAssertTrue([data writeToFile:destinationFile1 atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile2 atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager createSymbolicLinkAtPath:sourceFile2 withDestinationPath:@"A" error:&error]) {
            NSLog(@"Error in creating symlink: %@", error);
            XCTFail(@"Failed to create symlink");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testRegularFileToDirectoryChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSData *data = [NSData dataWithBytes:"loltest" length:7];
        XCTAssertTrue([data writeToFile:sourceFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:destinationFile withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTAssertFalse("Failed to create directory");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testDirectoryToRegularFileChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:sourceFile withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTAssertFalse("Failed to create directory");
        }
        
        NSData *data = [NSData dataWithBytes:"loltest" length:7];
        XCTAssertTrue([data writeToFile:destinationFile atomically:YES]);
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

// See issue #514 for more info
- (void)testDirectoryToSymlinkChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile1 = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *sourceFile2 = [sourceDirectory stringByAppendingPathComponent:@"Current"];
        NSString *sourceFile3 = [sourceFile2 stringByAppendingPathComponent:@"B"];
        
        NSString *destinationFile1 = [destinationDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile2 = [destinationFile1 stringByAppendingPathComponent:@"B"];
        NSString *destinationFile3 = [destinationDirectory stringByAppendingPathComponent:@"Current"];
        
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:sourceFile1 withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTAssertFalse("Failed to create directory A in source");
        }
        
        if (![fileManager createDirectoryAtPath:sourceFile2 withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTAssertFalse("Failed to create directory Current in source");
        }
        
        if (![fileManager createDirectoryAtPath:destinationFile1 withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTAssertFalse("Failed to create directory A in destination");
        }
        
        if (![fileManager createSymbolicLinkAtPath:destinationFile3 withDestinationPath:@"A/" error:&error]) {
            NSLog(@"Error in creating symlink: %@", error);
            XCTFail(@"Failed to create symlink");
        }
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile3 atomically:YES]);
        XCTAssertTrue([[self bigData1] writeToFile:destinationFile2 atomically:YES]);
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

// Opposite of the test method testDirectoryToSymlinkChange
- (void)testSymlinkToDirectoryChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile1 = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *sourceFile2 = [sourceFile1 stringByAppendingPathComponent:@"B"];
        NSString *sourceFile3 = [sourceDirectory stringByAppendingPathComponent:@"Current"];
        
        NSString *destinationFile1 = [destinationDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile2 = [destinationDirectory stringByAppendingPathComponent:@"Current"];
        NSString *destinationFile3 = [destinationFile2 stringByAppendingPathComponent:@"B"];
        
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:sourceFile1 withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTAssertFalse("Failed to create directory A in source");
        }
        
        if (![fileManager createDirectoryAtPath:destinationFile1 withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTAssertFalse("Failed to create directory A in destination");
        }
        
        if (![fileManager createDirectoryAtPath:destinationFile2 withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTAssertFalse("Failed to create directory Current in destination");
        }
        
        if (![fileManager createSymbolicLinkAtPath:sourceFile3 withDestinationPath:@"A/" error:&error]) {
            NSLog(@"Error in creating symlink: %@", error);
            XCTFail(@"Failed to create symlink");
        }
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile2 atomically:YES]);
        XCTAssertTrue([[self bigData1] writeToFile:destinationFile3 atomically:YES]);
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

@end
