//
//  SUCodeSigningVerifierTest.m
//  Sparkle
//
//  Created by Isaac Wankerl on 04/13/2015.
//  Copyright (c) 2015 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>
#import "SUCodeSigningVerifier.h"
#import "SUFileManager.h"

#define CALCULATOR_PATH @"/Applications/Calculator.app"

@interface SUCodeSigningVerifierTest : XCTestCase

@property (copy) NSURL *notSignedAppURL;
@property (copy) NSURL *validSignedAppURL;
@property (copy) NSURL *invalidSignedAppURL;
@property (copy) NSURL *calculatorCopyURL;

@end

@implementation SUCodeSigningVerifierTest

@synthesize notSignedAppURL = _notSignedAppURL;
@synthesize validSignedAppURL = _validSignedAppURL;
@synthesize invalidSignedAppURL = _invalidSignedAppURL;
@synthesize calculatorCopyURL = _calculatorCopyURL;

- (void)setUp
{
    [super setUp];

    NSBundle *unitTestBundle = [NSBundle bundleForClass:[self class]];
    NSString *unitTestBundleIdentifier = unitTestBundle.bundleIdentifier;
    NSString *zippedAppURL = [unitTestBundle pathForResource:@"SparkleTestCodeSignApp" ofType:@"zip"];

    SUFileManager *fileManager = [SUFileManager defaultManager];

    NSError *tempError = nil;
    NSURL *tempDir = [fileManager makeTemporaryDirectoryWithPreferredName:unitTestBundleIdentifier appropriateForDirectoryURL:[NSURL fileURLWithPath:zippedAppURL] error:&tempError];

    if (tempDir == nil) {
        XCTFail(@"Failed to create temporary directory with error: %@", tempError);
        return;
    }

    NSError *error = nil;
    if ([[NSFileManager defaultManager] createDirectoryAtURL:tempDir withIntermediateDirectories:YES attributes:nil error:&error]) {
        if ([self unzip:zippedAppURL toPath:tempDir.path]) {
            self.notSignedAppURL = [tempDir URLByAppendingPathComponent:@"SparkleTestCodeSignApp.app"];
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

    if (self.notSignedAppURL) {
        NSURL *tempDir = [self.notSignedAppURL URLByDeletingLastPathComponent];
        [[NSFileManager defaultManager] removeItemAtURL:tempDir error:nil];
    }
}

- (void)setupValidSignedApp
{
    NSError *error = nil;
    NSURL *tempDir = [self.notSignedAppURL URLByDeletingLastPathComponent];
    NSURL *signedAndValid = [tempDir URLByAppendingPathComponent:@"valid-signed.app"];

    [[NSFileManager defaultManager] removeItemAtURL:signedAndValid error:NULL];
    if (![[NSFileManager defaultManager] copyItemAtURL:self.notSignedAppURL toURL:signedAndValid error:&error]) {
        XCTFail("Failed to copy %@ to %@ with error: %@", self.notSignedAppURL, signedAndValid, error);
    }

    self.validSignedAppURL = signedAndValid;

    if (![self codesignAppURL:self.validSignedAppURL]) {
        XCTFail(@"Failed to codesign %@", self.validSignedAppURL);
    }
}

- (void)setupCalculatorCopy
{
    NSURL *tempDir = [self.notSignedAppURL URLByDeletingLastPathComponent];
    NSURL *calculatorCopy = [tempDir URLByAppendingPathComponent:@"calc.app"];

    [[NSFileManager defaultManager] removeItemAtURL:calculatorCopy error:NULL];

    // Make a copy of the signed calculator app so we can match signatures later
    // Matching signatures on ad-hoc signed apps does *not* work
    NSError *copyError = nil;
    // Don't check the return value of this operation - seems like on 10.11 the API can say it fails even though the operation really succeeds,
    // which sounds like some kind of (SIP / attribute?) bug
    [[NSFileManager defaultManager] copyItemAtURL:[NSURL fileURLWithPath:CALCULATOR_PATH] toURL:calculatorCopy error:&copyError];

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

    self.calculatorCopyURL = calculatorCopy;
}

- (void)setupInvalidSignedApp
{
    NSError *error = nil;
    NSURL *tempDir = [self.notSignedAppURL URLByDeletingLastPathComponent];
    NSURL *signedAndInvalid = [tempDir URLByAppendingPathComponent:@"invalid-signed.app"];

    [[NSFileManager defaultManager] removeItemAtURL:signedAndInvalid error:NULL];
    if ([[NSFileManager defaultManager] copyItemAtURL:self.notSignedAppURL toURL:signedAndInvalid error:&error]) {
        self.invalidSignedAppURL = signedAndInvalid;
        if ([self codesignAppURL:self.invalidSignedAppURL]) {
            NSURL *fileInAppBundleToRemove = [self.invalidSignedAppURL URLByAppendingPathComponent:@"Contents/Resources/test_app_only_dsa_pub.pem"];
            if (![[NSFileManager defaultManager] removeItemAtURL:fileInAppBundleToRemove error:&error]) {
                NSLog(@"Failed to remove %@ with error %@", fileInAppBundleToRemove, error);
            }
        }
        else {
            NSLog(@"Failed to codesign %@", self.invalidSignedAppURL);
        }
    }
    else {
        NSLog(@"Failed to copy %@ to %@ with error %@", self.notSignedAppURL, signedAndInvalid, error);
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

- (BOOL)codesignAppURL:(NSURL *)appPath
{
    BOOL success = NO;
    @try
    {
        // ad-hoc signing with the dash
        NSArray *arguments = @[ @"--force", @"--deep", @"--sign", @"-", appPath ];
        NSTask *task = [NSTask launchedTaskWithLaunchPath:@"/usr/bin/codesign" arguments:arguments];
        [task waitUntilExit];
        success = (task.terminationStatus == 0);
    }
    @catch (NSException *exception)
    {
        NSLog(@"exception: %@", exception);
    }
    return success;
}

- (void)testUnsignedApp
{
    XCTAssertFalse([SUCodeSigningVerifier bundleAtURLIsCodeSigned:self.notSignedAppURL], @"App not expected to be code signed");

    NSError *error = nil;
    XCTAssertFalse([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:self.notSignedAppURL error:&error], @"signature should not be valid as it's not code signed");
    XCTAssertNotNil(error, @"error should not be nil");
}

- (void)testValidSignedApp
{
    XCTAssertTrue([SUCodeSigningVerifier bundleAtURLIsCodeSigned:self.validSignedAppURL], @"App expected to be code signed");

    NSError *error = nil;
    XCTAssertTrue([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:self.validSignedAppURL error:&error], @"signature should be valid");
    XCTAssertNil(error, @"error should be nil");
}

- (void)testValidSignedCalculatorApp
{
    NSURL *appPath = [NSURL fileURLWithPath:CALCULATOR_PATH];
    XCTAssertTrue([SUCodeSigningVerifier bundleAtURLIsCodeSigned:appPath], @"App expected to be code signed");

    NSError *error = nil;
    XCTAssertTrue([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:appPath error:&error], @"signature should be valid");
    XCTAssertNil(error, @"error should be nil");
}

- (void)testValidMatchingSelf
{
    NSError *error = nil;
    NSURL *appPath = [NSURL fileURLWithPath:CALCULATOR_PATH];

    XCTAssertTrue([SUCodeSigningVerifier codeSignatureAtBundleURL:appPath matchesSignatureAtBundleURL:appPath error:&error], @"Our valid signed app expected to having matching signature to itself");
}

- (void)testValidMatching
{
    // We can't test our own app because matching with ad-hoc signed apps understandably does not succeed
    NSError *error = nil;
    NSURL *appPath = [NSURL fileURLWithPath:CALCULATOR_PATH];
    XCTAssertTrue([SUCodeSigningVerifier codeSignatureAtBundleURL:appPath matchesSignatureAtBundleURL:self.calculatorCopyURL error:&error], @"The calculator app is expected to have matching identity signature to its altered copy");
}

- (void)testInvalidMatching
{
    NSURL *appPath = [NSURL fileURLWithPath:CALCULATOR_PATH];
    NSError *error = nil;
    XCTAssertFalse([SUCodeSigningVerifier codeSignatureAtBundleURL:appPath matchesSignatureAtBundleURL:self.validSignedAppURL error:&error], @"Calculator app bundle expected to have different signature than our valid signed app");
}

- (void)testInvalidSignedApp
{
    XCTAssertTrue([SUCodeSigningVerifier bundleAtURLIsCodeSigned:self.invalidSignedAppURL], @"App expected to be code signed, but signature is invalid");

    NSError *error = nil;
    XCTAssertFalse([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:self.invalidSignedAppURL error:&error], @"signature should not be valid");
    XCTAssertNotNil(error, @"error should not be nil");
}

@end
