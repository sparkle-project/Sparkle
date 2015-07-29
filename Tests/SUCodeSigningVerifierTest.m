//
//  SUCodeSigningVerifierTest.m
//  Sparkle
//
//  Created by Isaac Wankerl on 04/13/2015.
//  Copyright (c) 2015 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>
#import "NTSynchronousTask.h"
#import "SUCodeSigningVerifier.h"

@interface SUCodeSigningVerifierTest : XCTestCase

@property (copy) NSString *notSignedAppPath;
@property (copy) NSString *validSignedAppPath;
@property (copy) NSString *invalidSignedAppPath;

@end

@implementation SUCodeSigningVerifierTest

@synthesize notSignedAppPath = _notSignedAppPath;
@synthesize validSignedAppPath = _validSignedAppPath;
@synthesize invalidSignedAppPath = _invalidSignedAppPath;

- (void)setUp
{
    [super setUp];

    NSBundle *unitTestBundle = [NSBundle bundleForClass:[self class]];
    NSString *unitTestBundleIdentifier = unitTestBundle.bundleIdentifier;
    NSString *zippedAppPath = [unitTestBundle pathForResource:@"SparkleTestCodeSignApp" ofType:@"zip"];
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:unitTestBundleIdentifier];
    NSError *error = nil;
    if ([[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:&error]) {
        if ([self unzip:zippedAppPath toPath:tempDir]) {
            self.notSignedAppPath = [tempDir stringByAppendingPathComponent:@"SparkleTestCodeSignApp.app"];
            [self setupValidSignedApp];
            [self setupInvalidSignedApp];
        }
        else {
            NSLog(@"Failed to unzip %@", zippedAppPath);
        }
    }
    else {
        NSLog(@"Failed to created dir %@ with error %@", tempDir, error);
    }
}

- (void)tearDown
{
    [super tearDown];
    
    if (self.notSignedAppPath) {
        [[NSFileManager defaultManager] removeItemAtPath:self.notSignedAppPath error:nil];
    }
    if (self.validSignedAppPath) {
        [[NSFileManager defaultManager] removeItemAtPath:self.validSignedAppPath error:nil];
    }
    if (self.invalidSignedAppPath) {
        [[NSFileManager defaultManager] removeItemAtPath:self.invalidSignedAppPath error:nil];
    }
}

- (void)setupValidSignedApp
{
    NSError *error = nil;
    NSString *tempDir = [self.notSignedAppPath stringByDeletingLastPathComponent];
    NSString *signedAndValid = [tempDir stringByAppendingPathComponent:@"valid-signed.app"];
    if ([[NSFileManager defaultManager] copyItemAtPath:self.notSignedAppPath toPath:signedAndValid error:&error]) {
        self.validSignedAppPath = signedAndValid;
        if (![self codesignAppPath:self.validSignedAppPath]) {
            NSLog(@"Failed to codesign %@", self.validSignedAppPath);
        }
    }
    else {
        NSLog(@"Failed to copy %@ to %@ with error %@", self.notSignedAppPath, signedAndValid, error);
    }
}

- (void)setupInvalidSignedApp
{
    NSError *error = nil;
    NSString *tempDir = [self.notSignedAppPath stringByDeletingLastPathComponent];
    NSString *signedAndInvalid = [tempDir stringByAppendingPathComponent:@"invalid-signed.app"];
    if ([[NSFileManager defaultManager] copyItemAtPath:self.notSignedAppPath toPath:signedAndInvalid error:&error]) {
        self.invalidSignedAppPath = signedAndInvalid;
        if ([self codesignAppPath:self.invalidSignedAppPath]) {
            NSString *fileInAppBundleToRemove = [self.invalidSignedAppPath stringByAppendingPathComponent:@"Contents/Resources/test_app_only_dsa_pub.pem"];
            if (![[NSFileManager defaultManager] removeItemAtPath:fileInAppBundleToRemove error:&error]) {
                NSLog(@"Failed to remove %@ with error %@", fileInAppBundleToRemove, error);
            }
        }
        else {
            NSLog(@"Failed to codesign %@", self.invalidSignedAppPath);
        }
    }
    else {
        NSLog(@"Failed to copy %@ to %@ with error %@", self.notSignedAppPath, signedAndInvalid, error);
    }
}

- (BOOL)unzip:(NSString *)zipPath toPath:(NSString *)destPath
{
    BOOL success = NO;
    @try
    {
        NTSynchronousTask *task = [[NTSynchronousTask alloc] init];
        NSArray *arguments = @[ zipPath ];
        [task run:@"/usr/bin/unzip" directory:destPath withArgs:arguments input:nil];
        success = ([task result] == 0);
    }
    @catch (NSException *exception)
    {
        NSLog(@"exception: %@", exception);
    }
    return success;
}

- (BOOL)codesignAppPath:(NSString *)appPath
{
    BOOL success = NO;
    @try
    {
        // ad-hoc signing with the dash
        NSArray *arguments = @[ @"--force", @"--deep", @"--sign", @"-", appPath ];
        NTSynchronousTask *task = [[NTSynchronousTask alloc] init];
        [task run:@"/usr/bin/codesign" directory:nil withArgs:arguments input:nil];
        success = ([task result] == 0);
    }
    @catch (NSException *exception)
    {
        NSLog(@"exception: %@", exception);
    }
    return success;
}

- (void)testUnsignedApp
{
    XCTAssertFalse([SUCodeSigningVerifier applicationAtPathIsCodeSigned:self.notSignedAppPath], @"App not expected to be code signed");

    NSError *error = nil;
    XCTAssertFalse([SUCodeSigningVerifier codeSignatureIsValidAtPath:self.notSignedAppPath error:&error], @"signature should not be valid as it's not code signed");
    XCTAssertNotNil(error, @"error should not be nil");
}

- (void)testValidSignedApp
{
    XCTAssertTrue([SUCodeSigningVerifier applicationAtPathIsCodeSigned:self.validSignedAppPath], @"App expected to be code signed");

    NSError *error = nil;
    XCTAssertTrue([SUCodeSigningVerifier codeSignatureIsValidAtPath:self.validSignedAppPath error:&error], @"signature should be valid");
    XCTAssertNil(error, @"error should be nil");
}

- (void)testValidSignedCalculatorApp
{
    NSString *appPath = @"/Applications/Calculator.app";
    XCTAssertTrue([SUCodeSigningVerifier applicationAtPathIsCodeSigned:appPath], @"App expected to be code signed");

    NSError *error = nil;
    XCTAssertTrue([SUCodeSigningVerifier codeSignatureIsValidAtPath:appPath error:&error], @"signature should be valid");
    XCTAssertNil(error, @"error should be nil");
}

- (void)testInvalidSignedApp
{
    XCTAssertTrue([SUCodeSigningVerifier applicationAtPathIsCodeSigned:self.invalidSignedAppPath], @"App expected to be code signed, but signature is invalid");

    NSError *error = nil;
    XCTAssertFalse([SUCodeSigningVerifier codeSignatureIsValidAtPath:self.invalidSignedAppPath error:&error], @"signature should not be valid");
    XCTAssertNotNil(error, @"error should not be nil");
}

@end
