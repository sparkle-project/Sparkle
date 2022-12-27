//
//  SUCodeSigningVerifierTest.m
//  Sparkle
//
//  Created by Isaac Wankerl on 04/13/2015.
//  Copyright (c) 2015 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "SUCodeSigningVerifier.h"
#import "SUAdHocCodeSigning.h"
#import "SUFileManager.h"

#if defined(__MAC_10_15)
// In macOS 10.15 and later, pre-installed apps are installed under the System folder
#define CALCULATOR_PATH @"/System/Applications/Calculator.app"
#else
#define CALCULATOR_PATH @"/Applications/Calculator.app"
#endif

@interface SUCodeSigningVerifierTest : XCTestCase
@end

@implementation SUCodeSigningVerifierTest
{
    NSURL *_notSignedAppURL;
    NSURL *_validSignedAppURL;
    NSURL *_invalidSignedAppURL;
    NSURL *_calculatorCopyURL;
}

+ (NSString *)calculatorApplicationPath
{
    NSString *applicationsDirectory = [NSSearchPathForDirectoriesInDomains(NSApplicationDirectory, NSSystemDomainMask, NO) objectAtIndex:0];
    NSString *calculatorPath = [applicationsDirectory stringByAppendingPathComponent:@"Calculator.app"];
    return calculatorPath;
}

- (void)setUp
{
    [super setUp];

    NSBundle *unitTestBundle = [NSBundle bundleForClass:[self class]];
    NSString *zippedAppURL = [unitTestBundle pathForResource:@"SparkleTestCodeSignApp" ofType:@"zip"];

    SUFileManager *fileManager = [[SUFileManager alloc] init];
    
    NSError *tempError = nil;
    NSURL *tempDir = [fileManager makeTemporaryDirectoryAppropriateForDirectoryURL:[NSURL fileURLWithPath:zippedAppURL] error:&tempError];

    if (tempDir == nil) {
        XCTFail(@"Failed to create temporary directory with error: %@", tempError);
        return;
    }

    NSError *error = nil;
    if ([[NSFileManager defaultManager] createDirectoryAtURL:tempDir withIntermediateDirectories:YES attributes:nil error:&error]) {
        if ([self unzip:zippedAppURL toPath:tempDir.path]) {
            _notSignedAppURL = [tempDir URLByAppendingPathComponent:@"SparkleTestCodeSignApp.app"];
            [self setupValidSignedApp];
            [self setupCalculatorCopy];
            [self setupInvalidSignedApp];
        }
        else {
            NSLog(@"Failed to unzip %@", zippedAppURL);
        }
    }
    else {
        NSLog(@"Failed to created dir %@ with error %@", tempDir, error);
    }
}

- (void)tearDown
{
    [super tearDown];

    if (_notSignedAppURL != nil) {
        NSURL *tempDir = [_notSignedAppURL URLByDeletingLastPathComponent];
        [[NSFileManager defaultManager] removeItemAtURL:tempDir error:nil];
    }
}

- (void)setupValidSignedApp
{
    NSError *error = nil;
    NSURL *tempDir = [_notSignedAppURL URLByDeletingLastPathComponent];
    NSURL *signedAndValid = [tempDir URLByAppendingPathComponent:@"valid-signed.app"];

    [[NSFileManager defaultManager] removeItemAtURL:signedAndValid error:NULL];
    if (![[NSFileManager defaultManager] copyItemAtURL:_notSignedAppURL toURL:signedAndValid error:&error]) {
        XCTFail("Failed to copy %@ to %@ with error: %@", _notSignedAppURL, signedAndValid, error);
    }

    _validSignedAppURL = signedAndValid;

    if (![self codesignAppURL:_validSignedAppURL]) {
        XCTFail(@"Failed to codesign %@", _validSignedAppURL);
    }
}

- (void)setupCalculatorCopy
{
    NSURL *tempDir = [_notSignedAppURL URLByDeletingLastPathComponent];
    NSURL *calculatorCopy = [tempDir URLByAppendingPathComponent:@"calc.app"];

    [[NSFileManager defaultManager] removeItemAtURL:calculatorCopy error:NULL];

    NSString *calculatorPath = [SUCodeSigningVerifierTest calculatorApplicationPath];
    // Make a copy of the signed calculator app so we can match signatures later
    // Matching signatures on ad-hoc signed apps does *not* work
    NSError *copyError = nil;
    // Don't check the return value of this operation - seems like on 10.11 the API can say it fails even though the operation really succeeds,
    // which sounds like some kind of (SIP / attribute?) bug
    [[NSFileManager defaultManager] copyItemAtURL:[NSURL fileURLWithPath:calculatorPath] toURL:calculatorCopy error:&copyError];

    if (![calculatorCopy checkResourceIsReachableAndReturnError:nil]) {
        XCTFail(@"Copied calculator application does not exist");
    }

    // Alter the signed copy slightly, this won't invalidate signature matching (although it will invalidate the integrity part of the signature)
    // Which is what we want. If a user alters an app bundle, we should still be able to update as long as its identity is still valid
    NSError *removeError = nil;
    NSURL *calculatorPkgInfo = [[calculatorCopy URLByAppendingPathComponent:@"Contents"] URLByAppendingPathComponent:@"PkgInfo"];
    XCTAssertNotNil(calculatorPkgInfo);
    if (![[NSFileManager defaultManager] removeItemAtURL:calculatorPkgInfo error:&removeError]) {
        XCTFail(@"Failed to remove file in calculator copy with error: %@", removeError);
    }

    _calculatorCopyURL = calculatorCopy;
}

- (void)setupInvalidSignedApp
{
    NSError *error = nil;
    NSURL *tempDir = [_notSignedAppURL URLByDeletingLastPathComponent];
    NSURL *signedAndInvalid = [tempDir URLByAppendingPathComponent:@"invalid-signed.app"];

    [[NSFileManager defaultManager] removeItemAtURL:signedAndInvalid error:NULL];
    if ([[NSFileManager defaultManager] copyItemAtURL:_notSignedAppURL toURL:signedAndInvalid error:&error]) {
        _invalidSignedAppURL = signedAndInvalid;
        if ([self codesignAppURL:_invalidSignedAppURL]) {
            NSURL *fileInAppBundleToRemove = [_invalidSignedAppURL URLByAppendingPathComponent:@"Contents/Resources/test_app_only_dsa_pub.pem"];
            if (![[NSFileManager defaultManager] removeItemAtURL:fileInAppBundleToRemove error:&error]) {
                NSLog(@"Failed to remove %@ with error %@", fileInAppBundleToRemove, error);
            }
        }
        else {
            NSLog(@"Failed to codesign %@", _invalidSignedAppURL);
        }
    }
    else {
        NSLog(@"Failed to copy %@ to %@ with error %@", _notSignedAppURL, signedAndInvalid, error);
    }
}

- (BOOL)unzip:(NSString *)zipPath toPath:(NSString *)destPath
{
    BOOL success = NO;
    @try
    {
        NSTask *task = [[NSTask alloc] init];
        task.launchPath = @"/usr/bin/unzip";
        task.currentDirectoryPath = destPath;
        task.arguments = @[zipPath];

        [task launch];
        [task waitUntilExit];
        success = (task.terminationStatus == 0);
    }
    @catch (NSException *exception)
    {
        NSLog(@"exception: %@", exception);
    }
    return success;
}

- (BOOL)codesignAppURL:(NSURL *)appURL
{
    return [SUAdHocCodeSigning codeSignApplicationAtPath:appURL.path];
}

- (void)testUnsignedApp
{
    XCTAssertFalse([SUCodeSigningVerifier bundleAtURLIsCodeSigned:_notSignedAppURL], @"App not expected to be code signed");

    NSError *error = nil;
    XCTAssertFalse([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:_notSignedAppURL error:&error], @"signature should not be valid as it's not code signed");
    XCTAssertNotNil(error, @"error should not be nil");
}

- (void)testValidSignedApp
{
    XCTAssertTrue([SUCodeSigningVerifier bundleAtURLIsCodeSigned:_validSignedAppURL], @"App expected to be code signed");

    NSError *error = nil;
    XCTAssertTrue([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:_validSignedAppURL error:&error], @"signature should be valid");
    XCTAssertNil(error, @"error should be nil");
}

- (void)testValidSignedCalculatorApp
{
    NSString *calculatorPath = [SUCodeSigningVerifierTest calculatorApplicationPath];
    NSURL *appPath = [NSURL fileURLWithPath:calculatorPath];
    XCTAssertTrue([SUCodeSigningVerifier bundleAtURLIsCodeSigned:appPath], @"App expected to be code signed");

    NSError *error = nil;
    XCTAssertTrue([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:appPath error:&error], @"signature should be valid");
    XCTAssertNil(error, @"error should be nil");
}

- (void)testValidMatchingSelf
{
    NSString *calculatorPath = [SUCodeSigningVerifierTest calculatorApplicationPath];
    NSError *error = nil;
    NSURL *appPath = [NSURL fileURLWithPath:calculatorPath];

    XCTAssertTrue([SUCodeSigningVerifier codeSignatureAtBundleURL:appPath matchesSignatureAtBundleURL:appPath error:&error], @"Our valid signed app expected to having matching signature to itself");
}

- (void)testValidMatching
{
    NSString *calculatorPath = [SUCodeSigningVerifierTest calculatorApplicationPath];
    // We can't test our own app because matching with ad-hoc signed apps understandably does not succeed
    NSError *error = nil;
    NSURL *appPath = [NSURL fileURLWithPath:calculatorPath];
    XCTAssertTrue([SUCodeSigningVerifier codeSignatureAtBundleURL:appPath matchesSignatureAtBundleURL:_calculatorCopyURL error:&error], @"The calculator app is expected to have matching identity signature to its altered copy");
}

- (void)testInvalidMatching
{
    NSString *calculatorPath = [SUCodeSigningVerifierTest calculatorApplicationPath];
    NSURL *appPath = [NSURL fileURLWithPath:calculatorPath];
    NSError *error = nil;
    XCTAssertFalse([SUCodeSigningVerifier codeSignatureAtBundleURL:appPath matchesSignatureAtBundleURL:_validSignedAppURL error:&error], @"Calculator app bundle expected to have different signature than our valid signed app");
}

- (void)testInvalidSignedApp
{
    XCTAssertTrue([SUCodeSigningVerifier bundleAtURLIsCodeSigned:_invalidSignedAppURL], @"App expected to be code signed, but signature is invalid");

    NSError *error = nil;
    XCTAssertFalse([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:_invalidSignedAppURL error:&error], @"signature should not be valid");
    XCTAssertNotNil(error, @"error should not be nil");
}

@end
