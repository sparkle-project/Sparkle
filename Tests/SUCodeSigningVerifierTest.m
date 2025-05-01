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

@interface SUCodeSigningVerifierTest : XCTestCase
@end

@implementation SUCodeSigningVerifierTest
{
    NSURL *_notSignedAppURL;
    NSURL *_validSignedAppURL;
    NSURL *_invalidSignedAppURL;
    NSURL *_devSignedAppURL;
    NSURL *_devSignedVersion2AppURL;
    NSURL *_devInvalidSignedAppURL;
    NSURL *_devSignedDiskImageURL;
    NSURL *_unsignedDiskImageURL;
    NSURL *_adhocSignedDiskImageURL;
}

- (void)setUp
{
    [super setUp];

    NSBundle *unitTestBundle = [NSBundle bundleForClass:[self class]];
    
    _devSignedDiskImageURL = [unitTestBundle URLForResource:@"DevSignedAppVersion2" withExtension:@"dmg"];
    _unsignedDiskImageURL = [unitTestBundle URLForResource:@"SparkleTestCodeSign_apfs" withExtension:@"dmg"];
    _adhocSignedDiskImageURL = [unitTestBundle URLForResource:@"SparkleTestCodeSign_apfs_lzma_aux_files_adhoc" withExtension:@"dmg"];
    
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
            [self setUpValidSignedApp];
            [self setUpDevSignedApps];
            [self setUpInvalidSignedApp];
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

- (void)setUpValidSignedApp
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

- (void)setUpDevSignedApps
{
    NSURL *tempDir = [_notSignedAppURL URLByDeletingLastPathComponent];
    NSURL *devSignedAppURL = [tempDir URLByAppendingPathComponent:@"DevSignedApp.app"];
    NSURL *devSignedAppVersion2URL = [tempDir URLByAppendingPathComponent:@"DevSignedAppVersion2.app"];
    NSURL *devInvalidSignedAppURL = [tempDir URLByAppendingPathComponent:@"DevInvalidSignedApp.app"];
    
    _devSignedAppURL = devSignedAppURL;
    _devSignedVersion2AppURL = devSignedAppVersion2URL;
    _devInvalidSignedAppURL = devInvalidSignedAppURL;

    [[NSFileManager defaultManager] removeItemAtURL:devSignedAppURL error:NULL];
    [[NSFileManager defaultManager] removeItemAtURL:devSignedAppVersion2URL error:NULL];
    [[NSFileManager defaultManager] removeItemAtURL:devInvalidSignedAppURL error:NULL];

    // Make a copy of a signed devID app so we can match signatures later
    // Matching signatures on ad-hoc signed apps does *not* work
    
    NSBundle *unitTestBundle = [NSBundle bundleForClass:[self class]];
    
    {
        NSString *zippedAppURL = [unitTestBundle pathForResource:@"DevSignedApp" ofType:@"zip"];
        if ([self unzip:zippedAppURL toPath:tempDir.path]) {
            BOOL copiedApp = [[NSFileManager defaultManager] copyItemAtURL:devSignedAppURL toURL:devInvalidSignedAppURL error:NULL];
            XCTAssertTrue(copiedApp);
            
            BOOL wroteData = [[NSData data] writeToURL:(NSURL * _Nonnull)[devInvalidSignedAppURL URLByAppendingPathComponent:@"Contents/Resources/foo"] atomically:YES];
            XCTAssertTrue(wroteData);
        } else {
            XCTFail(@"Failed to unzip dev signed app");
        }
    }
    
    {
        NSString *zippedAppURL = [unitTestBundle pathForResource:@"DevSignedAppVersion2" ofType:@"zip"];
        if (![self unzip:zippedAppURL toPath:tempDir.path]) {
            XCTFail(@"Failed to unzip dev signed app");
        }
    }
}

- (void)setUpInvalidSignedApp
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

- (void)testValidSignedDevIdApp
{
    XCTAssertTrue([SUCodeSigningVerifier bundleAtURLIsCodeSigned:_devSignedAppURL], @"App expected to be code signed");
    
    XCTAssertTrue([SUCodeSigningVerifier bundleAtURLIsCodeSigned:_devSignedVersion2AppURL], @"App expected to be code signed");

    {
        NSError *error = nil;
        XCTAssertTrue([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:_devSignedAppURL error:&error], @"signature should be valid");
        XCTAssertNil(error, @"error should be nil");
    }
    
    {
        NSError *error = nil;
        XCTAssertTrue([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:_devSignedVersion2AppURL error:&error], @"signature should be valid");
        XCTAssertNil(error, @"error should be nil");
    }
}

- (void)testInvalidSignedDevIdApp
{
    XCTAssertTrue([SUCodeSigningVerifier bundleAtURLIsCodeSigned:_devInvalidSignedAppURL], @"App expected to be code signed");

    NSError *error = nil;
    XCTAssertFalse([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:_devInvalidSignedAppURL error:&error], @"signature should be invalid");
    XCTAssertNotNil(error, @"error should be not be nil");
}

- (void)testValidMatchingSelf
{
    NSError *error = nil;
    
    XCTAssertTrue([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:_devSignedAppURL andMatchesSignatureAtBundleURL:_devSignedAppURL error:&error], @"Our valid signed app expected to having matching signature to itself");
}

- (void)testValidMatchingDevIdApp
{
    // We can't test our own app because matching with ad-hoc signed apps understandably does not succeed
    
    {
        NSError *error = nil;
        XCTAssertTrue([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:_devSignedAppURL andMatchesSignatureAtBundleURL:_devSignedVersion2AppURL error:&error], @"The dev ID signed app is expected to have a matching identity signature to a newer version");
        XCTAssertNil(error);
    }
    
    {
        NSError *error = nil;
        XCTAssertTrue([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:_devSignedVersion2AppURL andMatchesSignatureAtBundleURL:_devSignedAppURL error:&error], @"The dev ID signed app is expected to have a matching identity signature to an older version");
        XCTAssertNil(error);
    }
}

- (void)testValidMatchingDevIdDiskImage
{
    NSError *error = nil;
    XCTAssertTrue([SUCodeSigningVerifier codeSignatureIsValidAtDownloadURL:_devSignedDiskImageURL andMatchesDeveloperIDTeamFromOldBundleURL:_devSignedAppURL error:&error]);
    XCTAssertNil(error);
}

- (void)testInvalidMatchingDevIdDiskImageWithAppNoSigning
{
    NSError *error = nil;
    XCTAssertFalse([SUCodeSigningVerifier codeSignatureIsValidAtDownloadURL:_devSignedDiskImageURL andMatchesDeveloperIDTeamFromOldBundleURL:_notSignedAppURL error:&error]);
    XCTAssertNotNil(error);
}

- (void)testInvalidMatchingDevIdDiskImageWithAppAdhocSigning
{
    NSError *error = nil;
    XCTAssertFalse([SUCodeSigningVerifier codeSignatureIsValidAtDownloadURL:_devSignedDiskImageURL andMatchesDeveloperIDTeamFromOldBundleURL:_validSignedAppURL error:&error]);
    XCTAssertNotNil(error);
}

- (void)testInvalidMatchWithNoDiskImageSigning
{
    NSError *error = nil;
    XCTAssertFalse([SUCodeSigningVerifier codeSignatureIsValidAtDownloadURL:_unsignedDiskImageURL andMatchesDeveloperIDTeamFromOldBundleURL:_validSignedAppURL error:&error]);
    XCTAssertNotNil(error);
}

- (void)testInvalidMatchWithAdhocSignedDiskImage
{
    NSError *error = nil;
    XCTAssertFalse([SUCodeSigningVerifier codeSignatureIsValidAtDownloadURL:_adhocSignedDiskImageURL andMatchesDeveloperIDTeamFromOldBundleURL:_devSignedAppURL error:&error]);
    XCTAssertNotNil(error);
}

- (void)testInvalidMatchingWithBrokenBundle
{
    // We can't test our own app because matching with ad-hoc signed apps understandably does not succeed
    {
        NSError *error = nil;
        XCTAssertFalse([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:_devSignedAppURL andMatchesSignatureAtBundleURL:_invalidSignedAppURL error:&error], @"The dev ID signed app is expected to not have a matching identity signature to its altered invalid copy");
        XCTAssertNotNil(error);
    }
    
    {
        NSError *error = nil;
        XCTAssertFalse([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:_invalidSignedAppURL andMatchesSignatureAtBundleURL:_devSignedAppURL error:&error], @"The invalid dev ID signed app is expected to not have a matching identity signature to the valid version");
        XCTAssertNotNil(error);
    }
}

- (void)testInvalidMatching
{
    NSError *error = nil;
    
    XCTAssertFalse([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:_validSignedAppURL andMatchesSignatureAtBundleURL:_devSignedAppURL error:&error], @"Dev ID signed app bundle expected to have different signature than our adhoc valid signed app");
}

- (void)testInvalidSignedApp
{
    XCTAssertTrue([SUCodeSigningVerifier bundleAtURLIsCodeSigned:_invalidSignedAppURL], @"App expected to be code signed, but signature is invalid");

    NSError *error = nil;
    XCTAssertFalse([SUCodeSigningVerifier codeSignatureIsValidAtBundleURL:_invalidSignedAppURL error:&error], @"signature should not be valid");
    XCTAssertNotNil(error, @"error should not be nil");
}

@end
