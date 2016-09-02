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

@property (copy) NSString *notSignedAppPath;
@property (copy) NSString *notSignedAppURL;
@property (copy) NSString *validSignedAppPath;
@property (copy) NSString *invalidSignedAppPath;
@property (copy) NSString *calculatorCopyPath;

@end

@implementation SUCodeSigningVerifierTest

@synthesize notSignedAppPath = _notSignedAppPath;
@synthesize notSignedAppURL = _notSignedAppURL;
@synthesize validSignedAppPath = _validSignedAppPath;
@synthesize invalidSignedAppPath = _invalidSignedAppPath;
@synthesize calculatorCopyPath = _calculatorCopyPath;

- (void)setUp
{
    [super setUp];

    NSBundle *unitTestBundle = [NSBundle bundleForClass:[self class]];
    NSString *unitTestBundleIdentifier = unitTestBundle.bundleIdentifier;
    NSString *zippedAppPath = [unitTestBundle pathForResource:@"SparkleTestCodeSignApp" ofType:@"zip"];
    
    SUFileManager *fileManager = [SUFileManager defaultManager];
    
    NSError *tempError = nil;
    NSURL *tempDir = [fileManager makeTemporaryDirectoryWithPreferredName:unitTestBundleIdentifier appropriateForDirectoryURL:[NSURL fileURLWithPath:zippedAppPath] error:&tempError];
    
    if (tempDir == nil) {
        XCTFail(@"Failed to create temporary directory with error: %@", tempError);
        return;
    }
    
    NSString *tempDirPath = tempDir.path;
    XCTAssertNotNil(tempDirPath);
    
    NSError *error = nil;
    if ([[NSFileManager defaultManager] createDirectoryAtPath:tempDirPath withIntermediateDirectories:YES attributes:nil error:&error]) {
        if ([self unzip:zippedAppPath toPath:tempDirPath]) {
            self.notSignedAppPath = [tempDirPath stringByAppendingPathComponent:@"SparkleTestCodeSignApp.app"];
            self.notSignedAppURL = [NSURL fileURLWithPath:self.notSignedAppPath];
            [self setupValidSignedApp];
            [self setupCalculatorCopy];
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
        NSString *tempDir = [self.notSignedAppPath stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
    }
}

- (void)setupValidSignedApp
{
    NSError *error = nil;
    NSString *tempDir = [self.notSignedAppPath stringByDeletingLastPathComponent];
    NSString *signedAndValid = [tempDir stringByAppendingPathComponent:@"valid-signed.app"];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:signedAndValid]) {
        [[NSFileManager defaultManager] removeItemAtPath:signedAndValid error:NULL];
    }
    
    if (![[NSFileManager defaultManager] copyItemAtPath:self.notSignedAppPath toPath:signedAndValid error:&error]) {
        XCTFail("Failed to copy %@ to %@ with error: %@", self.notSignedAppPath, signedAndValid, error);
    }
    
    self.validSignedAppPath = signedAndValid;
    
    if (![self codesignAppPath:self.validSignedAppPath]) {
        XCTFail(@"Failed to codesign %@", self.validSignedAppPath);
    }
}

- (void)setupCalculatorCopy
{
    NSString *tempDir = [self.notSignedAppPath stringByDeletingLastPathComponent];
    NSString *calculatorCopy = [tempDir stringByAppendingPathComponent:@"calc.app"];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:calculatorCopy]) {
        [[NSFileManager defaultManager] removeItemAtPath:calculatorCopy error:NULL];
    }
    
    // Make a copy of the signed calculator app so we can match signatures later
    // Matching signatures on ad-hoc signed apps does *not* work
    NSError *copyError = nil;
    // Don't check the return value of this operation - seems like on 10.11 the API can say it fails even though the operation really succeeds,
    // which sounds like some kind of (SIP / attribute?) bug
    [[NSFileManager defaultManager] copyItemAtPath:CALCULATOR_PATH toPath:calculatorCopy error:&copyError];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:calculatorCopy]) {
        XCTFail(@"Copied calculator application does not exist");
    }
    
    // Alter the signed copy slightly, this won't invalidate signature matching (although it will invalidate the integrity part of the signature)
    // Which is what we want. If a user alters an app bundle, we should still be able to update as long as its identity is still valid
    NSError *removeError = nil;
    if (![[NSFileManager defaultManager] removeItemAtPath:[[calculatorCopy stringByAppendingPathComponent:@"Contents"] stringByAppendingPathComponent:@"PkgInfo"] error:&removeError]) {
        XCTFail(@"Failed to remove file in calculator copy with error: %@", removeError);
    }
    
    self.calculatorCopyPath = calculatorCopy;
}

- (void)setupInvalidSignedApp
{
    NSError *error = nil;
    NSString *tempDir = [self.notSignedAppPath stringByDeletingLastPathComponent];
    NSString *signedAndInvalid = [tempDir stringByAppendingPathComponent:@"invalid-signed.app"];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:signedAndInvalid]) {
        [[NSFileManager defaultManager] removeItemAtPath:signedAndInvalid error:NULL];
    }
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

- (BOOL)codesignAppPath:(NSString *)appPath
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
    XCTAssertTrue([SUCodeSigningVerifier bundleAtURLIsCodeSigned:self.validSignedAppPath], @"App expected to be code signed");

    NSError *error = nil;
    XCTAssertTrue([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:self.validSignedAppPath error:&error], @"signature should be valid");
    XCTAssertNil(error, @"error should be nil");
}

- (void)testValidSignedCalculatorApp
{
    NSString *appPath = CALCULATOR_PATH;
    XCTAssertTrue([SUCodeSigningVerifier bundleAtURLIsCodeSigned:appPath], @"App expected to be code signed");

    NSError *error = nil;
    XCTAssertTrue([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:appPath error:&error], @"signature should be valid");
    XCTAssertNil(error, @"error should be nil");
}

- (void)testValidMatchingSelf
{
    NSError *error = nil;
    XCTAssertTrue([SUCodeSigningVerifier codeSignatureAtBundleURL:CALCULATOR_PATH matchesSignatureAtBundleURL:CALCULATOR_PATH error:&error], @"Our valid signed app expected to having matching signature to itself");
}

- (void)testValidMatching
{
    // We can't test our own app because matching with ad-hoc signed apps understandably does not succeed
    NSError *error = nil;
    XCTAssertTrue([SUCodeSigningVerifier codeSignatureAtBundleURL:CALCULATOR_PATH matchesSignatureAtBundleURL:self.calculatorCopyPath error:&error], @"The calculator app is expected to have matching identity signature to its altered copy");
}

- (void)testInvalidMatching
{
    NSString *appPath = CALCULATOR_PATH;
    NSError *error = nil;
    XCTAssertFalse([SUCodeSigningVerifier codeSignatureAtBundleURL:appPath matchesSignatureAtBundleURL:self.validSignedAppPath error:&error], @"Calculator app bundle expected to have different signature than our valid signed app");
}

- (void)testInvalidSignedApp
{
    XCTAssertTrue([SUCodeSigningVerifier bundleAtURLIsCodeSigned:self.invalidSignedAppPath], @"App expected to be code signed, but signature is invalid");

    NSError *error = nil;
    XCTAssertFalse([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:self.invalidSignedAppPath error:&error], @"signature should not be valid");
    XCTAssertNotNil(error, @"error should not be nil");
}

@end
