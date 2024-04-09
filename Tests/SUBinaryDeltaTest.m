//
//  SUBinaryDeltaTest.m
//  Sparkle
//
//  Created by Jake Petroules on 2014-08-22.
//  Copyright (c) 2014 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "SUBinaryDeltaCommon.h"
#import "SUBinaryDeltaCreate.h"
#import "SUBinaryDeltaApply.h"
#import <sys/stat.h>
#include <sys/xattr.h>

@interface SUBinaryDeltaTest : XCTestCase

@end

typedef void (^SUDeltaHandler)(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory);

@implementation SUBinaryDeltaTest

- (void)testTemporaryDirectory
{
    NSString *tmp1 = temporaryDirectory(@"Sparklęエンジン");
    NSString *tmp2 = temporaryDirectory(@"Sparklęエンジン");
    NSLog(@"Temporary directories: %@, %@", tmp1, tmp2);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-messaging-id"
    XCTAssertNotEqualObjects(tmp1, tmp2);
#pragma clang diagnostic pop
    XCTAssert(YES, @"Pass");
}

- (void)testTemporaryFile
{
    NSString *tmp1 = temporaryFilename(@"Sparklęエンジン");
    NSString *tmp2 = temporaryFilename(@"Sparklęエンジン");
    NSLog(@"Temporary files: %@, %@", tmp1, tmp2);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-messaging-id"
    XCTAssertNotEqualObjects(tmp1, tmp2);
#pragma clang diagnostic pop
    XCTAssert(YES, @"Pass");
}

- (BOOL)createAndApplyPatchUsingVersion:(SUBinaryDeltaMajorVersion)majorVersion compressionMode:(SPUDeltaCompressionMode)compressionMode beforeDiffHandler:(SUDeltaHandler)beforeDiffHandler afterDiffHandler:(SUDeltaHandler)afterDiffHandler afterPatchHandler:(SUDeltaHandler)afterPatchHandler
{
    NSString *sourceDirectory = temporaryDirectory(@"Spąrkle_temp1エンジン");
    NSString *destinationDirectory = temporaryDirectory(@"Spąrkle_temp2エンジン");

    NSString *diffFile = temporaryFilename(@"Spąrkle_diffエンジン");
    NSString *patchDirectory = temporaryDirectory(@"Spąrkle_patchエンジン");

    XCTAssertNotNil(sourceDirectory);
    XCTAssertNotNil(destinationDirectory);
    XCTAssertNotNil(diffFile);
    
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    
    if (beforeDiffHandler != nil) {
        beforeDiffHandler(fileManager, sourceDirectory, destinationDirectory);
    }
    
    NSError *createDiffError = nil;
    BOOL createdDiff = createBinaryDelta(sourceDirectory, destinationDirectory, diffFile, majorVersion, compressionMode, 0, NO, &createDiffError);
    if (!createdDiff) {
        NSLog(@"Creating binary diff failed with error: %@", createDiffError);
    } else if (afterDiffHandler != nil) {
        afterDiffHandler(fileManager, sourceDirectory, destinationDirectory);
    }
    
    NSError *applyDiffError = nil;
    BOOL appliedDiff = NO;
    if (createdDiff) {
        if (applyBinaryDelta(sourceDirectory, patchDirectory, diffFile, NO, ^(__unused double progress){}, &applyDiffError)) {
            appliedDiff = YES;
            
            if (afterPatchHandler != nil) {
                afterPatchHandler(fileManager, destinationDirectory, patchDirectory);
            }
        } else {
            NSLog(@"Applying binary diff failed with error: %@", applyDiffError);
        }
    }
    
    XCTAssertTrue([fileManager removeItemAtPath:sourceDirectory error:nil]);
    XCTAssertTrue([fileManager removeItemAtPath:destinationDirectory error:nil]);
    XCTAssertTrue([fileManager removeItemAtPath:patchDirectory error:nil]);
    XCTAssertTrue([fileManager removeItemAtPath:diffFile error:nil]);
    
    return appliedDiff;
}

- (BOOL)createAndApplyPatchWithBeforeDiffHandler:(SUDeltaHandler)beforeDiffHandler afterDiffHandler:(SUDeltaHandler)afterDiffHandler afterPatchHandler:(SUDeltaHandler)afterPatchHandler
{
#if SPARKLE_BUILD_LEGACY_DELTA_SUPPORT
    BOOL testingVersion2Delta = YES;
#else
    BOOL testingVersion2Delta = NO;
#endif
    return [self createAndApplyPatchWithBeforeDiffHandler:beforeDiffHandler afterDiffHandler:afterDiffHandler afterPatchHandler:afterPatchHandler testingVersion2Delta:testingVersion2Delta];
}

- (BOOL)createAndApplyPatchWithBeforeDiffHandler:(SUDeltaHandler)beforeDiffHandler afterDiffHandler:(SUDeltaHandler)afterDiffHandler afterPatchHandler:(SUDeltaHandler)afterPatchHandler testingVersion2Delta:(BOOL)testingVersion2Delta
{
    XCTAssertEqual(SUBinaryDeltaMajorVersion3, SUBinaryDeltaMajorVersionLatest);
    
    BOOL version3DeltaFormatWithLZMASuccess = [self createAndApplyPatchUsingVersion:SUBinaryDeltaMajorVersion3 compressionMode:SPUDeltaCompressionModeLZMA beforeDiffHandler:beforeDiffHandler afterDiffHandler:afterDiffHandler afterPatchHandler:afterPatchHandler];
    
#if SPARKLE_BUILD_BZIP2_DELTA_SUPPORT
    BOOL version3DeltaFormatWithBZIP2Success = [self createAndApplyPatchUsingVersion:SUBinaryDeltaMajorVersion3 compressionMode:SPUDeltaCompressionModeBzip2 beforeDiffHandler:beforeDiffHandler afterDiffHandler:afterDiffHandler afterPatchHandler:afterPatchHandler];
#endif
    
    BOOL version3DeltaFormatWithZLIBSuccess = [self createAndApplyPatchUsingVersion:SUBinaryDeltaMajorVersion3 compressionMode:SPUDeltaCompressionModeZLIB beforeDiffHandler:beforeDiffHandler afterDiffHandler:afterDiffHandler afterPatchHandler:afterPatchHandler];
    
    BOOL version2FormatSuccess = !testingVersion2Delta || [self createAndApplyPatchUsingVersion:SUBinaryDeltaMajorVersion2 compressionMode:SPUDeltaCompressionModeDefault beforeDiffHandler:beforeDiffHandler afterDiffHandler:afterDiffHandler afterPatchHandler:afterPatchHandler];
    
    return (
        version3DeltaFormatWithLZMASuccess &&
#if SPARKLE_BUILD_BZIP2_DELTA_SUPPORT
        version3DeltaFormatWithBZIP2Success &&
#endif
        version3DeltaFormatWithZLIBSuccess &&
        version2FormatSuccess
    );
}

- (void)createAndApplyPatchWithHandler:(SUDeltaHandler)handler
{
    BOOL success = [self createAndApplyPatchWithBeforeDiffHandler:handler afterDiffHandler:nil afterPatchHandler:nil];
    XCTAssertTrue(success);
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

- (void)testNoFilesDiff
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        XCTAssertTrue([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testEmptyDataDiff
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSData *emptyData = [NSData data];
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"AĄエンジン"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"AĄエンジン"];

        XCTAssertTrue([emptyData writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([emptyData writeToFile:destinationFile atomically:YES]);
        
        XCTAssertTrue([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testDifferentlyNamedEmptyDataDiff
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSData *emptyData = [NSData data];
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"B"];
        
        XCTAssertTrue([emptyData writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([emptyData writeToFile:destinationFile atomically:YES]);
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testEmptyDirectoryDiff
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:sourceFile withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTFail("Failed to create directory");
        }
        
        if (![fileManager createDirectoryAtPath:destinationFile withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTFail("Failed to create directory");
        }
        
        XCTAssertTrue([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testDifferentlyNamedEmptyDirectoryDiff
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"B"];
        
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:sourceFile withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTFail("Failed to create directory");
        }
        
        if (![fileManager createDirectoryAtPath:destinationFile withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTFail("Failed to create directory");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testSameNonexistentSymlinkDiff
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSError *error = nil;
        if (![fileManager createSymbolicLinkAtPath:sourceFile withDestinationPath:@"B" error:&error]) {
            NSLog(@"Failed creating empty symlink with error: %@", error);
            XCTFail("Failed to create empty symlink");
        }
        
        if (![fileManager createSymbolicLinkAtPath:destinationFile withDestinationPath:@"B" error:&error]) {
            NSLog(@"Failed creating empty symlink with error: %@", error);
            XCTFail("Failed to create empty symlink");
        }
        
        XCTAssertTrue([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testDifferentNonexistentSymlinkDiff
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSError *error = nil;
        if (![fileManager createSymbolicLinkAtPath:sourceFile withDestinationPath:@"B" error:&error]) {
            NSLog(@"Failed creating empty symlink with error: %@", error);
            XCTFail("Failed to create empty symlink");
        }
        
        if (![fileManager createSymbolicLinkAtPath:destinationFile withDestinationPath:@"C" error:&error]) {
            NSLog(@"Failed creating empty symlink with error: %@", error);
            XCTFail("Failed to create empty symlink");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testNonexistentSymlinkPermissionDiff
{
    [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSError *error = nil;
        if (![fileManager createSymbolicLinkAtPath:sourceFile withDestinationPath:@"B" error:&error]) {
            NSLog(@"Failed creating empty symlink to source with error: %@", error);
            XCTFail("Failed to create empty symlink");
        }
        
        if (![fileManager createSymbolicLinkAtPath:destinationFile withDestinationPath:@"B" error:&error]) {
            NSLog(@"Failed creating empty symlink to destination with error: %@", error);
            XCTFail("Failed to create empty symlink");
        }
        
        if (lchmod([sourceFile fileSystemRepresentation], 0777) != 0) {
            NSLog(@"Change Permission Error..");
            XCTFail(@"Failed setting file permissions");
        }
        
        // 0755 and 0777 should result in the same hash
        XCTAssertTrue([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    } afterDiffHandler:nil afterPatchHandler:^(NSFileManager *fileManager, NSString * __unused sourceDirectory, NSString *destinationDirectory) {
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSError *error = nil;
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:destinationFile error:&error];
        if (attributes == nil) {
            NSLog(@"Failed to retrieve attributes with error: %@", error);
            XCTFail("Failed to retrieve symlink attributes");
        }
        
        NSNumber *permissionAttribute = attributes[NSFilePosixPermissions];
        XCTAssertNotNil(permissionAttribute);
        
        unsigned short permissions = permissionAttribute.unsignedShortValue & PERMISSION_FLAGS;
        XCTAssertEqual(permissions, VALID_SYMBOLIC_LINK_PERMISSIONS);
    }];
}

- (void)testNonexistentSymlinkPermissionBadDiff
{
    // Even though destination has a 0777 symlink permission, we only respect 0755 for symlinks
    [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSError *error = nil;
        if (![fileManager createSymbolicLinkAtPath:sourceFile withDestinationPath:@"B" error:&error]) {
            NSLog(@"Failed creating empty symlink to source with error: %@", error);
            XCTFail("Failed to create empty symlink");
        }
        
        if (![fileManager createSymbolicLinkAtPath:destinationFile withDestinationPath:@"B" error:&error]) {
            NSLog(@"Failed creating empty symlink to destination with error: %@", error);
            XCTFail("Failed to create empty symlink");
        }
        
        if (lchmod([destinationFile fileSystemRepresentation], 0777) != 0) {
            NSLog(@"Change Permission Error..");
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertTrue([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    } afterDiffHandler:nil afterPatchHandler:^(NSFileManager *fileManager, NSString * __unused sourceDirectory, NSString *destinationDirectory) {
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSError *error = nil;
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:destinationFile error:&error];
        if (attributes == nil) {
            NSLog(@"Failed to retrieve attributes with error: %@", error);
            XCTFail("Failed to retrieve symlink attributes");
        }
        
        NSNumber *permissionAttribute = attributes[NSFilePosixPermissions];
        XCTAssertNotNil(permissionAttribute);
        
        unsigned short permissions = permissionAttribute.unsignedShortValue & PERMISSION_FLAGS;
        XCTAssertEqual(permissions, VALID_SYMBOLIC_LINK_PERMISSIONS);
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

- (void)testInvalidSource
{
    BOOL success = [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[NSData data] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[NSData dataWithBytes:"loltest" length:7] writeToFile:destinationFile atomically:YES]);
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    } afterDiffHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *__unused destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[NSData dataWithBytes:"testt" length:5] writeToFile:sourceFile atomically:YES]);
    } afterPatchHandler:nil];
    XCTAssertFalse(success);
}

- (NSData *)bigData1
{
    const size_t bufferSize = 4096*32;
    uint8_t *buffer = calloc(1, bufferSize);
    XCTAssertTrue(buffer != NULL);
    
    return [NSData dataWithBytesNoCopy:buffer length:bufferSize];
}

- (NSData *)bigData2
{
    const size_t bufferSize = 4096*32;
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

// Make sure old version patches are no longer supported
- (void)testRegularFileAddedWithVersion1Delta
{
    XCTAssertFalse([self createAndApplyPatchUsingVersion:SUBinaryDeltaMajorVersion1 compressionMode:SPUDeltaCompressionModeDefault beforeDiffHandler:nil afterDiffHandler:nil afterPatchHandler:nil]);
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
            XCTFail("Failed to create directory");
        }
        
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile3 atomically:YES]);
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testDirectoryAddedWithOddPermissions
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
            XCTFail("Failed to create directory");
        }
        
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile3 atomically:YES]);
        
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0777} ofItemAtPath:destinationFile2 error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testDirectoryPermissionsChanged
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceDir = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destDir = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:sourceDir withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTFail("Failed to create directory");
        }
        
        if (![fileManager createDirectoryAtPath:destDir withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTFail("Failed to create directory");
        }
        
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0777} ofItemAtPath:destDir error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
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
            XCTFail("Failed to create directory");
        }
        
        XCTAssertTrue([[self bigData2] writeToFile:sourceFile3 atomically:YES]);
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testRegularFileMove
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A/B/C/D/E/F/G/H/I/J/K/L/M/N/O/P/Q/R"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A/B/C/D/E/F/G/H/I/J/K/L/M/N/O/P/Q/R2"];
        
        [fileManager createDirectoryAtURL:[NSURL fileURLWithPath:sourceFile.stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
        
        [fileManager createDirectoryAtURL:[NSURL fileURLWithPath:destinationFile.stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
        
        NSData *data = [NSData dataWithBytes:"loltes" length:6];
        XCTAssertTrue([data writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile atomically:YES]);
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testLargerRegularFileMoveWithFileInPlace
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A/B/C/D/E/F/G/H/I/J/K/L/M/N/O/P/Q/R"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A/B/C/D/E/F/G/H/I/J/K/L/M/N/O/P/Q/R2"];
        NSString *destinationFile2 = [destinationDirectory stringByAppendingPathComponent:@"A/B/C/D/E/F/G/H/I/J/K/L/M/N/O/P/Q/R"];
        NSString *destinationFile3 = [destinationDirectory stringByAppendingPathComponent:@"A/B/C/D/E/F/G/H/I/J/K/L/M/N/O/P/Q/X"];
        
        [fileManager createDirectoryAtURL:[NSURL fileURLWithPath:sourceFile.stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
        
        [fileManager createDirectoryAtURL:[NSURL fileURLWithPath:destinationFile.stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
        
        NSData *data = [self bigData2];
        XCTAssertTrue([data writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile2 atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile3 atomically:YES]);
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testRegularLargerFileMove
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"B"];
        
        NSData *data = [self bigData2];
        XCTAssertTrue([data writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile atomically:YES]);
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testRegularFileMoveWithPermissionChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A/B/C/D/E/F/G/H/I/J/K/L/M/N/O/P/Q/R"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A/B/C/D/E/F/G/H/I/J/K/L/M/N/O/P/Q/R2"];
        
        [fileManager createDirectoryAtURL:[NSURL fileURLWithPath:sourceFile.stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
        
        [fileManager createDirectoryAtURL:[NSURL fileURLWithPath:destinationFile.stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
        
        NSData *data = [NSData dataWithBytes:"loltes" length:6];
        XCTAssertTrue([data writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile atomically:YES]);
        
        if (chmod([destinationFile fileSystemRepresentation], 0777) != 0) {
            NSLog(@"Change Permission Error..");
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testRegularLargerFileMoveWithPermissionChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"B"];
        
        NSData *data = [self bigData2];
        XCTAssertTrue([data writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile atomically:YES]);
        
        if (chmod([destinationFile fileSystemRepresentation], 0777) != 0) {
            NSLog(@"Change Permission Error..");
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testRegularLargerFileMoveWithNoWritablePermissionInSource
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"B"];
        
        NSData *data = [self bigData2];
        XCTAssertTrue([data writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile atomically:YES]);
        
        if (chmod([sourceFile fileSystemRepresentation], 0444) != 0) {
            NSLog(@"Change Permission Error..");
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testRegularLargerFileMoveWithNoWritablePermissionInDestination
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"B"];
        
        NSData *data = [self bigData2];
        XCTAssertTrue([data writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile atomically:YES]);
        
        if (chmod([destinationFile fileSystemRepresentation], 0444) != 0) {
            NSLog(@"Change Permission Error..");
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testRegularLargerFileMoveWithNoWritablePermissionInSourceAndOtherFileAtDestinationPresent
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"B"];
        NSString *destinationFile2 = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSData *data = [self bigData2];
        XCTAssertTrue([data writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile atomically:YES]);
        XCTAssertTrue([[self bigData1] writeToFile:destinationFile2 atomically:YES]);
        
        if (chmod([sourceFile fileSystemRepresentation], 0444) != 0) {
            NSLog(@"Change Permission Error..");
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testRegularLargerFileMoveWithNoWritablePermissionInDestinationAndOtherFileAtDestinationPresent
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"B"];
        NSString *destinationFile2 = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSData *data = [self bigData2];
        XCTAssertTrue([data writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile atomically:YES]);
        XCTAssertTrue([[self bigData1] writeToFile:destinationFile2 atomically:YES]);
        
        if (chmod([destinationFile fileSystemRepresentation], 0444) != 0) {
            NSLog(@"Change Permission Error..");
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testRegularLargerFileMoveWithNoWritablePermissionInSourceAndOtherFileAtSourcePresent
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"B"];
        NSString *sourceFile2 = [destinationDirectory stringByAppendingPathComponent:@"B"];
        
        NSData *data = [self bigData2];
        XCTAssertTrue([data writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile atomically:YES]);
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile2 atomically:YES]);
        
        if (chmod([sourceFile fileSystemRepresentation], 0444) != 0) {
            NSLog(@"Change Permission Error..");
            XCTFail(@"Failed setting file permissions");
        }
        
        if (chmod([sourceFile2 fileSystemRepresentation], 0444) != 0) {
            NSLog(@"Change Permission Error..");
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testRegularLargerFileMoveWithNoWritablePermissionInDestinationAndOtherFileAtSourcePresent
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"B"];
        NSString *sourceFile2 = [destinationDirectory stringByAppendingPathComponent:@"B"];
        
        NSData *data = [self bigData2];
        XCTAssertTrue([data writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile atomically:YES]);
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile2 atomically:YES]);
        
        if (chmod([destinationFile fileSystemRepresentation], 0444) != 0) {
            NSLog(@"Change Permission Error..");
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testSymbolicLinkMove
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A/B/C/D/E/F/G/H/I/J/K/L/M/N/O/P/Q/R"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A/B/C/D/E/F/G/H/I/J/K/L/M/N/O/P/Q/R2"];
        
        [fileManager createDirectoryAtURL:[NSURL fileURLWithPath:sourceFile.stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
        
        [fileManager createDirectoryAtURL:[NSURL fileURLWithPath:destinationFile.stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
        
        NSError *error = nil;
        
        if (![fileManager createSymbolicLinkAtPath:sourceFile withDestinationPath:@"C" error:&error]) {
            NSLog(@"Error in creating symlink: %@", error);
            XCTFail(@"Failed to create symlink");
        }
        
        if (![fileManager createSymbolicLinkAtPath:destinationFile withDestinationPath:@"C" error:&error]) {
            NSLog(@"Error in creating symlink: %@", error);
            XCTFail(@"Failed to create symlink");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testLargerSymbolicLinkMove
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"B"];
        
        NSError *error = nil;
        
        NSString *destinationPath = @"loltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltest";
        
        if (![fileManager createSymbolicLinkAtPath:sourceFile withDestinationPath:destinationPath error:&error]) {
            NSLog(@"Error in creating symlink: %@", error);
            XCTFail(@"Failed to create symlink");
        }
        
        if (![fileManager createSymbolicLinkAtPath:destinationFile withDestinationPath:destinationPath error:&error]) {
            NSLog(@"Error in creating symlink: %@", error);
            XCTFail(@"Failed to create symlink");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testSymbolicLinkMoveWithPermissionChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A/B/C/D/E/F/G/H/I/J/K/L/M/N/O/P/Q/R"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A/B/C/D/E/F/G/H/I/J/K/L/M/N/O/P/Q/R2"];
        
        [fileManager createDirectoryAtURL:[NSURL fileURLWithPath:sourceFile.stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
        
        [fileManager createDirectoryAtURL:[NSURL fileURLWithPath:destinationFile.stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:NULL];
        
        NSError *error = nil;
        
        if (![fileManager createSymbolicLinkAtPath:sourceFile withDestinationPath:@"C" error:&error]) {
            NSLog(@"Error in creating symlink: %@", error);
            XCTFail(@"Failed to create symlink");
        }
        
        if (![fileManager createSymbolicLinkAtPath:destinationFile withDestinationPath:@"C" error:&error]) {
            NSLog(@"Error in creating symlink: %@", error);
            XCTFail(@"Failed to create symlink");
        }
        
        if (lchmod([destinationFile fileSystemRepresentation], 0777) != 0) {
            NSLog(@"Change Permission Error..");
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testLargerSymbolicLinkMoveWithPermissionChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"B"];
        
        NSError *error = nil;
        
        NSString *destinationPath = @"loltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltest";
        
        if (![fileManager createSymbolicLinkAtPath:sourceFile withDestinationPath:destinationPath error:&error]) {
            NSLog(@"Error in creating symlink: %@", error);
            XCTFail(@"Failed to create symlink");
        }
        
        if (![fileManager createSymbolicLinkAtPath:destinationFile withDestinationPath:destinationPath error:&error]) {
            NSLog(@"Error in creating symlink: %@", error);
            XCTFail(@"Failed to create symlink");
        }
        
        if (lchmod([destinationFile fileSystemRepresentation], 0777) != 0) {
            NSLog(@"Change Permission Error..");
            XCTFail(@"Failed setting file permissions");
        }
        
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

- (void)testRemovingSymlink
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        
        NSError *error = nil;
        if (![fileManager createSymbolicLinkAtPath:sourceFile withDestinationPath:@"B" error:&error]) {
            NSLog(@"Error in creating symlink: %@", error);
            XCTFail(@"Failed to create symlink");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testAddingSymlink
{
    [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSError *error = nil;
        if (![fileManager createSymbolicLinkAtPath:destinationFile withDestinationPath:@"B" error:&error]) {
            NSLog(@"Error in creating symlink: %@", error);
            XCTFail(@"Failed to create symlink");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    } afterDiffHandler:nil afterPatchHandler:^(NSFileManager *fileManager, NSString * __unused sourceDirectory, NSString *destinationDirectory) {
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSError *error = nil;
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:destinationFile error:&error];
        if (attributes == nil) {
            NSLog(@"Failed to retrieve attributes with error: %@", error);
            XCTFail("Failed to retrieve symlink attributes");
        }
        
        NSNumber *permissionAttribute = attributes[NSFilePosixPermissions];
        XCTAssertNotNil(permissionAttribute);
        
        // Test default symlink permissions are correct
        unsigned short permissions = permissionAttribute.unsignedShortValue & PERMISSION_FLAGS;
        XCTAssertEqual(permissions, VALID_SYMBOLIC_LINK_PERMISSIONS);
    }];
}

- (void)testAddingSymlinkWithWrongPermissions
{
    [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSError *error = nil;
        if (![fileManager createSymbolicLinkAtPath:destinationFile withDestinationPath:@"B" error:&error]) {
            NSLog(@"Error in creating symlink: %@", error);
            XCTFail(@"Failed to create symlink");
        }
        
        if (lchmod([destinationFile fileSystemRepresentation], 0777) != 0) {
            NSLog(@"Change Permission Error..");
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    } afterDiffHandler:nil afterPatchHandler:^(NSFileManager *fileManager, NSString * __unused sourceDirectory, NSString *destinationDirectory) {
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSError *error = nil;
        NSDictionary *attributes = [fileManager attributesOfItemAtPath:destinationFile error:&error];
        if (attributes == nil) {
            NSLog(@"Failed to retrieve attributes with error: %@", error);
            XCTFail("Failed to retrieve symlink attributes");
        }
        
        NSNumber *permissionAttribute = attributes[NSFilePosixPermissions];
        XCTAssertNotNil(permissionAttribute);
        
        // Test that we only respect valid symlink permissions for >= version 3 deltas
        unsigned short permissions = permissionAttribute.unsignedShortValue & PERMISSION_FLAGS;
        XCTAssertEqual(permissions, VALID_SYMBOLIC_LINK_PERMISSIONS);
    } testingVersion2Delta:NO];
}

- (void)testSmallFilePermissionChangeWithNoContentChange
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
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testBigFilePermissionChangeWithNoContentChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSData *data = [self bigData1];
        XCTAssertTrue([data writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0755} ofItemAtPath:destinationFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testSmallFilePermissionChangeWithContentChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[NSData data] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[NSData dataWithBytes:@"lawl" length:4] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0755} ofItemAtPath:destinationFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testBigFilePermissionChangeWithContentChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0755} ofItemAtPath:destinationFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testBigFilePermissionChangeInDirectoriesWithContentChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceA = [sourceDirectory stringByAppendingPathComponent:@"Contents/Hello/"];
        NSString *destinationB = [destinationDirectory stringByAppendingPathComponent:@"Contents/Meek/"];
        
        XCTAssertTrue([fileManager createDirectoryAtPath:sourceA withIntermediateDirectories:YES attributes:NULL error:NULL]);
        XCTAssertTrue([fileManager createDirectoryAtPath:destinationB withIntermediateDirectories:YES attributes:NULL error:NULL]);
        
        NSString *sourceFile = [sourceA stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationB stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0755} ofItemAtPath:destinationFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testBigFileChangeInDirectoriesWithContentChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceA = [sourceDirectory stringByAppendingPathComponent:@"Contents/Hello/"];
        NSString *destinationA = [destinationDirectory stringByAppendingPathComponent:@"Contents/Meek/"];
        
        XCTAssertTrue([fileManager createDirectoryAtPath:sourceA withIntermediateDirectories:YES attributes:NULL error:NULL]);
        XCTAssertTrue([fileManager createDirectoryAtPath:destinationA withIntermediateDirectories:YES attributes:NULL error:NULL]);
        
        NSString *sourceFile = [sourceA stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationA stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testBigFileChangeInDirectoriesWithContentChangeAndNoWritablePermissionInSource
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceA = [sourceDirectory stringByAppendingPathComponent:@"Contents/Hello/"];
        NSString *destinationA = [destinationDirectory stringByAppendingPathComponent:@"Contents/Meek/"];
        
        XCTAssertTrue([fileManager createDirectoryAtPath:sourceA withIntermediateDirectories:YES attributes:NULL error:NULL]);
        XCTAssertTrue([fileManager createDirectoryAtPath:destinationA withIntermediateDirectories:YES attributes:NULL error:NULL]);
        
        NSString *sourceFile = [sourceA stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationA stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0444} ofItemAtPath:sourceFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testBigFileChangeInDirectoriesWithContentChangeAndNoWritablePermissionInDestination
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceA = [sourceDirectory stringByAppendingPathComponent:@"Contents/Hello/"];
        NSString *destinationA = [destinationDirectory stringByAppendingPathComponent:@"Contents/Meek/"];
        
        XCTAssertTrue([fileManager createDirectoryAtPath:sourceA withIntermediateDirectories:YES attributes:NULL error:NULL]);
        XCTAssertTrue([fileManager createDirectoryAtPath:destinationA withIntermediateDirectories:YES attributes:NULL error:NULL]);
        
        NSString *sourceFile = [sourceA stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationA stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0444} ofItemAtPath:destinationFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testMultipleBigFileChangeInDirectoriesWithContentChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceA = [sourceDirectory stringByAppendingPathComponent:@"Contents/Hello/"];
        NSString *sourceA2 = [sourceDirectory stringByAppendingPathComponent:@"Contents/whaat/"];
        NSString *destinationB = [destinationDirectory stringByAppendingPathComponent:@"Contents/Meek/"];
        
        XCTAssertTrue([fileManager createDirectoryAtPath:sourceA withIntermediateDirectories:YES attributes:NULL error:NULL]);
        XCTAssertTrue([fileManager createDirectoryAtPath:sourceA2 withIntermediateDirectories:YES attributes:NULL error:NULL]);
        XCTAssertTrue([fileManager createDirectoryAtPath:destinationB withIntermediateDirectories:YES attributes:NULL error:NULL]);
        
        NSString *sourceFile = [sourceA stringByAppendingPathComponent:@"A"];
        NSString *sourceFile2 = [sourceA2 stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationB stringByAppendingPathComponent:@"A"];
        
        NSMutableData *data2 = [NSMutableData dataWithData:[self bigData1]];
        uint32_t foo = 100;
        [data2 appendBytes:&foo length:sizeof(foo)];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([data2 writeToFile:sourceFile2 atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testSmallFileNoWritablePermissionInSourceWithNoContentChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[NSData dataWithBytes:@"lawl" length:4] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[NSData dataWithBytes:@"lawl" length:4] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0444} ofItemAtPath:sourceFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testSmallFileNoWritablePermissionInDestinationWithNoContentChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[NSData dataWithBytes:@"lawl" length:4] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[NSData dataWithBytes:@"lawl" length:4] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0444} ofItemAtPath:destinationFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testBigFileNoWritablePermissionInSourceWithNoContentChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData1] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0444} ofItemAtPath:sourceFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testBigFileNoWritablePermissionInDestinationWithNoContentChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData1] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0444} ofItemAtPath:destinationFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testSmallFileNoWritablePermissionInSourceWithContentChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[NSData data] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[NSData dataWithBytes:@"lawl" length:4] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0444} ofItemAtPath:sourceFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testSmallFileNoWritablePermissionInDestinationWithContentChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[NSData data] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[NSData dataWithBytes:@"lawl" length:4] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0444} ofItemAtPath:destinationFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testBigFileNoWritablePermissionInSourceWithContentChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0444} ofItemAtPath:sourceFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testBigFileNoWritablePermissionInDestinationWithContentChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0444} ofItemAtPath:destinationFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testFileSystemCompression
{
    [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile2 = [destinationDirectory stringByAppendingPathComponent:@"A2"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        
        {
            // We only track executable files to decide if we want to apply file system compression over the entire bundle
            int lchmodResult = lchmod(destinationFile.fileSystemRepresentation, 0755);
            XCTAssertEqual(lchmodResult, 0);
        }
        
        NSTask *dittoTask = [[NSTask alloc] init];
        dittoTask.executableURL = [NSURL fileURLWithPath:@"/usr/bin/ditto" isDirectory:NO];
        
        dittoTask.arguments = @[@"--hfsCompression", destinationFile, destinationFile2];
        
        NSError *launchError = nil;
        BOOL launched = [dittoTask launchAndReturnError:&launchError];
        if (!launched) {
            XCTFail(@"Failed to launch ditto: %@", launchError);
        }
        [dittoTask waitUntilExit];
        
        XCTAssertEqual(dittoTask.terminationStatus, 0);
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    } afterDiffHandler:nil afterPatchHandler:^(NSFileManager *__unused fileManager, NSString *__unused sourceDirectory, NSString *destinationDirectory) {
        
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile2 = [destinationDirectory stringByAppendingPathComponent:@"A2"];
        
        // Both files should have file system compression applied
        {
            struct stat statStruct = {0};
            int result = lstat(destinationFile.fileSystemRepresentation, &statStruct);
            XCTAssertEqual(result, 0);
            
            if ((statStruct.st_flags & UF_COMPRESSED) == 0) {
                XCTFail(@"First destination file is not compressed!");
            }
        }
        {
            struct stat statStruct = {0};
            int result = lstat(destinationFile2.fileSystemRepresentation, &statStruct);
            XCTAssertEqual(result, 0);
            
            if ((statStruct.st_flags & UF_COMPRESSED) == 0) {
                XCTFail(@"Second destination file is not compressed!");
            }
        }
    } testingVersion2Delta:NO];
}

- (void)testNoFileSystemCompression
{
    [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile2 = [destinationDirectory stringByAppendingPathComponent:@"A2"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile2 atomically:YES]);
        
        {
            // We only usually track executable files to decide if we want to apply file system compression over the entire bundle
            int lchmodResult = lchmod(destinationFile.fileSystemRepresentation, 0755);
            XCTAssertEqual(lchmodResult, 0);
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    } afterDiffHandler:nil afterPatchHandler:^(NSFileManager *__unused fileManager, NSString *__unused sourceDirectory, NSString *destinationDirectory) {
        
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile2 = [destinationDirectory stringByAppendingPathComponent:@"A2"];
        
        // Both files should not have file system compression applied
        {
            struct stat statStruct = {0};
            int result = lstat(destinationFile.fileSystemRepresentation, &statStruct);
            XCTAssertEqual(result, 0);
            
            if ((statStruct.st_flags & UF_COMPRESSED) != 0) {
                XCTFail(@"First destination file is compressed!");
            }
        }
        {
            struct stat statStruct = {0};
            int result = lstat(destinationFile2.fileSystemRepresentation, &statStruct);
            XCTAssertEqual(result, 0);
            
            if ((statStruct.st_flags & UF_COMPRESSED) != 0) {
                XCTFail(@"Second destination file is compressed!");
            }
        }
    } testingVersion2Delta:NO];
}

- (void)testFrameworkVersionChanged
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceA = [sourceDirectory stringByAppendingPathComponent:@"Frameworks/Foo.framework/Versions/A/"];
        NSString *destinationB = [destinationDirectory stringByAppendingPathComponent:@"Frameworks/Foo.framework/Versions/B/"];
        
        XCTAssertTrue([fileManager createDirectoryAtPath:sourceA withIntermediateDirectories:YES attributes:NULL error:NULL]);
        XCTAssertTrue([fileManager createDirectoryAtPath:destinationB withIntermediateDirectories:YES attributes:NULL error:NULL]);
        
        NSString *sourceFile = [sourceA stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationB stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testFrameworkExecutableVersionChanged
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceA = [sourceDirectory stringByAppendingPathComponent:@"Frameworks/Foo.framework/Versions/A/"];
        NSString *destinationB = [destinationDirectory stringByAppendingPathComponent:@"Frameworks/Foo.framework/Versions/B/"];
        
        XCTAssertTrue([fileManager createDirectoryAtPath:sourceA withIntermediateDirectories:YES attributes:NULL error:NULL]);
        XCTAssertTrue([fileManager createDirectoryAtPath:destinationB withIntermediateDirectories:YES attributes:NULL error:NULL]);
        
        NSString *sourceFile = [sourceA stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationB stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0755} ofItemAtPath:sourceFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0755} ofItemAtPath:destinationFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testFrameworkVersionChangedWithPermissionChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceA = [sourceDirectory stringByAppendingPathComponent:@"Frameworks/Foo.framework/Versions/A/"];
        NSString *destinationB = [destinationDirectory stringByAppendingPathComponent:@"Frameworks/Foo.framework/Versions/B/"];
        
        XCTAssertTrue([fileManager createDirectoryAtPath:sourceA withIntermediateDirectories:YES attributes:NULL error:NULL]);
        XCTAssertTrue([fileManager createDirectoryAtPath:destinationB withIntermediateDirectories:YES attributes:NULL error:NULL]);
        
        NSString *sourceFile = [sourceA stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationB stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0755} ofItemAtPath:destinationFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testDirectoryPermissionChangeWithContentChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile1 = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *sourceFile2 = [sourceFile1 stringByAppendingPathComponent:@"B"];
        
        NSString *destinationFile1 = [destinationDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile2 = [destinationFile1 stringByAppendingPathComponent:@"B"];
        
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:sourceFile1 withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTFail("Failed to create directory");
        }
        
        if (![fileManager createDirectoryAtPath:destinationFile1 withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTFail("Failed to create directory");
        }
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile2 atomically:YES]);
        XCTAssertTrue([[self bigData1] writeToFile:destinationFile2 atomically:YES]);
        
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0766} ofItemAtPath:sourceFile1 error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0755} ofItemAtPath:destinationFile1 error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testDirectoryChangeWithExecutableContentChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile1 = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *sourceFile2 = [sourceFile1 stringByAppendingPathComponent:@"B"];
        
        NSString *destinationFile1 = [destinationDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile2 = [destinationFile1 stringByAppendingPathComponent:@"B"];
        
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:sourceFile1 withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTFail("Failed to create directory");
        }
        
        if (![fileManager createDirectoryAtPath:destinationFile1 withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTFail("Failed to create directory");
        }
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile2 atomically:YES]);
        XCTAssertTrue([[self bigData1] writeToFile:destinationFile2 atomically:YES]);
        
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0755} ofItemAtPath:sourceFile1 error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0755} ofItemAtPath:destinationFile1 error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertTrue([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testOddPermissionsInAfterTree
{
    BOOL success = [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSData *data = [NSData dataWithBytes:"loltest" length:7];
        XCTAssertTrue([data writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0777} ofItemAtPath:destinationFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    } afterDiffHandler:nil afterPatchHandler:nil];
    XCTAssertTrue(success);
}

- (void)testOddChangingPermissionsWithBigFilesInBothTrees
{
    BOOL success = [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0777} ofItemAtPath:sourceFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0774} ofItemAtPath:destinationFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    } afterDiffHandler:nil afterPatchHandler:nil];
    XCTAssertTrue(success);
}

- (void)testOddPermissionsWithBigFilesInBothTrees
{
    BOOL success = [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0777} ofItemAtPath:sourceFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0777} ofItemAtPath:destinationFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    } afterDiffHandler:nil afterPatchHandler:nil];
    XCTAssertTrue(success);
}

- (void)testBadPermissionsInBeforeTree
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        NSData *data = [NSData dataWithBytes:"loltest" length:7];
        XCTAssertTrue([data writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0777} ofItemAtPath:sourceFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        XCTAssertFalse([self testDirectoryHashEqualityWithSource:sourceDirectory destination:destinationDirectory]);
    }];
}

- (void)testInvalidRegularFileWithACLInBeforeTree
{
    BOOL success = [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString * __unused destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[NSData dataWithBytes:"loltest" length:7] writeToFile:sourceFile atomically:YES]);
        
        acl_t acl = acl_init(1);
        
        acl_entry_t entry;
        XCTAssertEqual(0, acl_create_entry(&acl, &entry));
        
        acl_permset_t permset;
        XCTAssertEqual(0, acl_get_permset(entry, &permset));
        
        XCTAssertEqual(0, acl_add_perm(permset, ACL_SEARCH));
        
        XCTAssertEqual(0, acl_set_link_np([sourceFile fileSystemRepresentation], ACL_TYPE_EXTENDED, acl));
        
        XCTAssertEqual(0, acl_free(acl));
    } afterDiffHandler:nil afterPatchHandler:nil];
    
    XCTAssertFalse(success);
}

- (void)testInvalidRegularFileWithACLInAfterTree
{
    BOOL success = [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *__unused fileManager, NSString *__unused sourceDirectory, NSString *destinationDirectory) {
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[NSData dataWithBytes:"loltest" length:7] writeToFile:destinationFile atomically:YES]);
        
        acl_t acl = acl_init(1);
        
        acl_entry_t entry;
        XCTAssertEqual(0, acl_create_entry(&acl, &entry));
        
        acl_permset_t permset;
        XCTAssertEqual(0, acl_get_permset(entry, &permset));
        
        XCTAssertEqual(0, acl_add_perm(permset, ACL_SEARCH));
        
        XCTAssertEqual(0, acl_set_link_np([destinationFile fileSystemRepresentation], ACL_TYPE_EXTENDED, acl));
        
        XCTAssertEqual(0, acl_free(acl));
        
    } afterDiffHandler:nil afterPatchHandler:nil];
    
    XCTAssertFalse(success);
}

- (void)testInvalidDirectoryWithACLInBeforeTree
{
    BOOL success = [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString * __unused destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([fileManager createDirectoryAtPath:sourceFile withIntermediateDirectories:NO attributes:nil error:nil]);
        
        acl_t acl = acl_init(1);
        
        acl_entry_t entry;
        XCTAssertEqual(0, acl_create_entry(&acl, &entry));
        
        acl_permset_t permset;
        XCTAssertEqual(0, acl_get_permset(entry, &permset));
        
        XCTAssertEqual(0, acl_add_perm(permset, ACL_SEARCH));
        
        XCTAssertEqual(0, acl_set_link_np([sourceFile fileSystemRepresentation], ACL_TYPE_EXTENDED, acl));
        
        XCTAssertEqual(0, acl_free(acl));
    } afterDiffHandler:nil afterPatchHandler:nil];
    
    XCTAssertFalse(success);
}

- (void)testInvalidDirectoryWithACLInAfterTree
{
    BOOL success = [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *fileManager, NSString * __unused sourceDirectory, NSString *destinationDirectory) {
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([fileManager createDirectoryAtPath:destinationFile withIntermediateDirectories:NO attributes:nil error:nil]);
        
        acl_t acl = acl_init(1);
        
        acl_entry_t entry;
        XCTAssertEqual(0, acl_create_entry(&acl, &entry));
        
        acl_permset_t permset;
        XCTAssertEqual(0, acl_get_permset(entry, &permset));
        
        XCTAssertEqual(0, acl_add_perm(permset, ACL_SEARCH));
        
        XCTAssertEqual(0, acl_set_link_np([destinationFile fileSystemRepresentation], ACL_TYPE_EXTENDED, acl));
        
        XCTAssertEqual(0, acl_free(acl));
    } afterDiffHandler:nil afterPatchHandler:nil];
    
    XCTAssertFalse(success);
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

- (void)testLargerRegularFileToSymlinkChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile1 = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *sourceFile2 = [sourceDirectory stringByAppendingPathComponent:@"B"];
        
        NSString *destinationFile1 = [destinationDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile2 = [destinationDirectory stringByAppendingPathComponent:@"B"];
        
        NSData *data = [NSData dataWithBytes:"loltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltest" length:420];
        
        XCTAssertTrue([data writeToFile:sourceFile1 atomically:YES]);
        XCTAssertTrue([data writeToFile:sourceFile2 atomically:YES]);
        
        XCTAssertTrue([data writeToFile:destinationFile1 atomically:YES]);
        
        NSString *destination = @"loltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltest";
        
        NSError *error = nil;
        if (![fileManager createSymbolicLinkAtPath:destinationFile2 withDestinationPath:destination error:&error]) {
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
        
        NSData *data = [NSData dataWithBytes:"loltes" length:6];
        
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

- (void)testLargerSymlinkToRegularFileChange
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile1 = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *sourceFile2 = [sourceDirectory stringByAppendingPathComponent:@"B"];
        
        NSString *destinationFile1 = [destinationDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile2 = [destinationDirectory stringByAppendingPathComponent:@"B"];
        
        NSData *data = [NSData dataWithBytes:"loltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltest" length:420];
        
        XCTAssertTrue([data writeToFile:sourceFile1 atomically:YES]);
        
        XCTAssertTrue([data writeToFile:destinationFile1 atomically:YES]);
        XCTAssertTrue([data writeToFile:destinationFile2 atomically:YES]);
        
        NSString *destination = @"loltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltestloltest";
        NSError *error = nil;
        if (![fileManager createSymbolicLinkAtPath:sourceFile2 withDestinationPath:destination error:&error]) {
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
        
        NSData *data = [NSData dataWithBytes:"loltes" length:6];
        XCTAssertTrue([data writeToFile:sourceFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:destinationFile withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTFail("Failed to create directory");
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
            XCTFail("Failed to create directory");
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
            XCTFail("Failed to create directory A in source");
        }
        
        if (![fileManager createDirectoryAtPath:sourceFile2 withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTFail("Failed to create directory Current in source");
        }
        
        if (![fileManager createDirectoryAtPath:destinationFile1 withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTFail("Failed to create directory A in destination");
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
            XCTFail("Failed to create directory A in source");
        }
        
        if (![fileManager createDirectoryAtPath:destinationFile1 withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTFail("Failed to create directory A in destination");
        }
        
        if (![fileManager createDirectoryAtPath:destinationFile2 withIntermediateDirectories:NO attributes:nil error:&error]) {
            NSLog(@"Failed creating directory with error: %@", error);
            XCTFail("Failed to create directory Current in destination");
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

- (void)testInvalidCodeSignatureExtendedAttributeInBeforeTree
{
    BOOL success = [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[NSData data] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[NSData dataWithBytes:"loltest" length:7] writeToFile:destinationFile atomically:YES]);
        
        // the actual data doesn't matter for testing purposes
        const char xattrValue[] = "hello";
        
        XCTAssertEqual(0, setxattr([sourceFile fileSystemRepresentation], APPLE_CODE_SIGN_XATTR_CODE_DIRECTORY_KEY, xattrValue, sizeof(xattrValue), 0, XATTR_CREATE));
        XCTAssertEqual(0, setxattr([sourceFile fileSystemRepresentation], APPLE_CODE_SIGN_XATTR_CODE_REQUIREMENTS_KEY, xattrValue, sizeof(xattrValue), 0, XATTR_CREATE));
        XCTAssertEqual(0, setxattr([sourceFile fileSystemRepresentation], APPLE_CODE_SIGN_XATTR_CODE_SIGNATURE_KEY, xattrValue, sizeof(xattrValue), 0, XATTR_CREATE));
    } afterDiffHandler:nil afterPatchHandler:nil];
    XCTAssertFalse(success);
}

- (void)testInvalidCodeSignatureExtendedAttributeInAfterTree
{
    BOOL success = [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[NSData data] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[NSData dataWithBytes:"loltest" length:7] writeToFile:destinationFile atomically:YES]);
        
        // the actual data doesn't matter for testing purposes
        const char xattrValue[] = "hello";
        
        XCTAssertEqual(0, setxattr([destinationFile fileSystemRepresentation], APPLE_CODE_SIGN_XATTR_CODE_DIRECTORY_KEY, xattrValue, sizeof(xattrValue), 0, XATTR_CREATE));
        XCTAssertEqual(0, setxattr([destinationFile fileSystemRepresentation], APPLE_CODE_SIGN_XATTR_CODE_REQUIREMENTS_KEY, xattrValue, sizeof(xattrValue), 0, XATTR_CREATE));
        XCTAssertEqual(0, setxattr([destinationFile fileSystemRepresentation], APPLE_CODE_SIGN_XATTR_CODE_SIGNATURE_KEY, xattrValue, sizeof(xattrValue), 0, XATTR_CREATE));
    } afterDiffHandler:nil afterPatchHandler:nil];
    XCTAssertFalse(success);
}

- (void)testCreatingPatchWithCustomIconInBeforeTree
{
    BOOL success = [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[NSData data] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[NSData dataWithBytes:"loltest" length:7] writeToFile:destinationFile atomically:YES]);
        
        NSImage *iconImage = [NSImage imageNamed:NSImageNameAdvanced];
        XCTAssertNotNil(iconImage);
        
        BOOL setIcon = [[NSWorkspace sharedWorkspace] setIcon:iconImage forFile:sourceDirectory options:0];
        XCTAssertTrue(setIcon);
    } afterDiffHandler:nil afterPatchHandler:nil];
    XCTAssertFalse(success);
}

- (void)testCreatingPatchWithCustomIconInAfterTree
{
    BOOL success = [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[NSData data] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[NSData dataWithBytes:"loltest" length:7] writeToFile:destinationFile atomically:YES]);
        
        NSImage *iconImage = [NSImage imageNamed:NSImageNameAdvanced];
        XCTAssertNotNil(iconImage);
        
        BOOL setIcon = [[NSWorkspace sharedWorkspace] setIcon:iconImage forFile:destinationDirectory options:0];
        XCTAssertTrue(setIcon);
    } afterDiffHandler:nil afterPatchHandler:nil];
    XCTAssertFalse(success);
}

- (void)testApplyingPatchAfterSettingCustomIcon
{
    BOOL success = [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceFile = [sourceDirectory stringByAppendingPathComponent:@"A"];
        NSString *destinationFile = [destinationDirectory stringByAppendingPathComponent:@"A"];
        
        XCTAssertTrue([[NSData data] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[NSData dataWithBytes:"loltest" length:7] writeToFile:destinationFile atomically:YES]);
    } afterDiffHandler:^(NSFileManager *__unused fileManager, NSString *sourceDirectory, NSString *__unused destinationDirectory) {
        NSImage *iconImage = [NSImage imageNamed:NSImageNameAdvanced];
        XCTAssertNotNil(iconImage);
        
        BOOL setIcon = [[NSWorkspace sharedWorkspace] setIcon:iconImage forFile:sourceDirectory options:0];
        XCTAssertTrue(setIcon);
    } afterPatchHandler:nil];
    XCTAssertTrue(success);
}

- (void)testRegularSparkleFrameworkPresence
{
    [self createAndApplyPatchWithHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceA = [sourceDirectory stringByAppendingPathComponent:@"Frameworks/Sparkle.framework/Versions/A/"];
        NSString *destinationB = [destinationDirectory stringByAppendingPathComponent:@"Frameworks/Sparkle.framework/Versions/B/"];
        
        XCTAssertTrue([fileManager createDirectoryAtPath:sourceA withIntermediateDirectories:YES attributes:NULL error:NULL]);
        XCTAssertTrue([fileManager createDirectoryAtPath:destinationB withIntermediateDirectories:YES attributes:NULL error:NULL]);
        
        NSString *sourceFile = [sourceA stringByAppendingPathComponent:@"Sparkle"];
        NSString *destinationFile = [destinationB stringByAppendingPathComponent:@"Sparkle"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0755} ofItemAtPath:sourceFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0755} ofItemAtPath:destinationFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
    }];
}

- (void)testInvalidSparkleFrameworkInBeforeTree
{
    BOOL success = [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceA = [sourceDirectory stringByAppendingPathComponent:@"Frameworks/Sparkle.framework/Versions/A/"];
        NSString *destinationB = [destinationDirectory stringByAppendingPathComponent:@"Frameworks/Sparkle.framework/Versions/B/"];
        
        XCTAssertTrue([fileManager createDirectoryAtPath:sourceA withIntermediateDirectories:YES attributes:NULL error:NULL]);
        XCTAssertTrue([fileManager createDirectoryAtPath:destinationB withIntermediateDirectories:YES attributes:NULL error:NULL]);
        
        NSString *sourceFile = [sourceA stringByAppendingPathComponent:@"Sparkle"];
        NSString *destinationFile = [destinationB stringByAppendingPathComponent:@"Sparkle"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        // Use invalid permission mode 0777
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0777} ofItemAtPath:sourceFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0755} ofItemAtPath:destinationFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
    } afterDiffHandler:nil afterPatchHandler:nil];
    
    XCTAssertFalse(success);
}

- (void)testInvalidSparkleFrameworkInAfterTree
{
    BOOL success = [self createAndApplyPatchWithBeforeDiffHandler:^(NSFileManager *fileManager, NSString *sourceDirectory, NSString *destinationDirectory) {
        NSString *sourceA = [sourceDirectory stringByAppendingPathComponent:@"Frameworks/Sparkle.framework/Versions/A/"];
        NSString *destinationB = [destinationDirectory stringByAppendingPathComponent:@"Frameworks/Sparkle.framework/Versions/B/"];
        
        XCTAssertTrue([fileManager createDirectoryAtPath:sourceA withIntermediateDirectories:YES attributes:NULL error:NULL]);
        XCTAssertTrue([fileManager createDirectoryAtPath:destinationB withIntermediateDirectories:YES attributes:NULL error:NULL]);
        
        NSString *sourceFile = [sourceA stringByAppendingPathComponent:@"Sparkle"];
        NSString *destinationFile = [destinationB stringByAppendingPathComponent:@"Sparkle"];
        
        XCTAssertTrue([[self bigData1] writeToFile:sourceFile atomically:YES]);
        XCTAssertTrue([[self bigData2] writeToFile:destinationFile atomically:YES]);
        
        NSError *error = nil;
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0755} ofItemAtPath:sourceFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
        
        // Use invalid permission mode 0700
        if (![fileManager setAttributes:@{NSFilePosixPermissions : @0700} ofItemAtPath:destinationFile error:&error]) {
            NSLog(@"Change Permission Error: %@", error);
            XCTFail(@"Failed setting file permissions");
        }
    } afterDiffHandler:nil afterPatchHandler:nil];
    
    XCTAssertFalse(success);
}

@end
