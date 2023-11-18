//
//  SUSignatureVerifierTest.m
//  Sparkle
//
//  Created by Kornel on 25/07/2014.
//  Copyright (c) 2014 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "SUSignatureVerifier.h"
#import "SUSignatures.h"

@interface SUSignatureVerifierTest : XCTestCase
@end

@implementation SUSignatureVerifierTest
{
    NSString *_testFile;
    NSString *_pubDSAKeyFile;
    NSString *_pubEdKey;
}

- (void)setUp
{
    [super setUp];

    _testFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"signed-test-file" ofType:@"txt"];
    _pubDSAKeyFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"test-pubkey" ofType:@"pem"];
    _pubEdKey = @"rhHib+w769W2/6/t+oM1ZxgjBB93BfBKMLO0Qo1etQs=";
}

- (void)testVerifyFileAtPathUsingDSA
{
    NSString *pubKey = [NSString stringWithContentsOfFile:_pubDSAKeyFile encoding:NSASCIIStringEncoding error:nil];
    XCTAssertNotNil(pubKey, @"Public key must be readable");

    NSString *validSig = @"MCwCFCIHCIYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ==";

    NSError *error = nil;
    
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
    XCTAssertTrue([self checkFile:_testFile
                       withDSAKey:pubKey
                        signature:validSig
                            error:&error],
                  @"Expected valid signature: %@", error);
#else
    XCTAssertFalse([self checkFile:_testFile
                        withDSAKey:pubKey
                         signature:validSig
                             error:&error],
                  @"Expected DSA verification to fail: %@", error);
#endif

    XCTAssertFalse([self checkFile:_testFile
                        withDSAKey:@"lol"
                         signature:validSig
                             error:&error],
                   @"Invalid pubkey: %@", error);

    XCTAssertFalse([self checkFile:_pubDSAKeyFile
                        withDSAKey:pubKey
                         signature:validSig
                             error:&error],
                   @"Wrong file checked: %@", error);

    XCTAssertFalse([self checkFile:_testFile
                        withDSAKey:pubKey
                         signature:@"MCwCFCIHCiYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ=="
                             error:&error],
                   @"Expected invalid signature: %@", error);

#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
    XCTAssertTrue([self checkFile:_testFile
                       withDSAKey:pubKey
                        signature:@"MC0CFAsKO7cq2q7L5/FWe6ybVIQkwAwSAhUA2Q8GKsE309eugi/v3Kh1W3w3N8c="
                            error:&error],
                  @"Expected valid signature: %@", error);
#else
    XCTAssertFalse([self checkFile:_testFile
                        withDSAKey:pubKey
                         signature:@"MC0CFAsKO7cq2q7L5/FWe6ybVIQkwAwSAhUA2Q8GKsE309eugi/v3Kh1W3w3N8c="
                             error:&error],
                  @"Expected DSA verification to fail: %@", error);
#endif

    XCTAssertFalse([self checkFile:_testFile
                        withDSAKey:pubKey
                         signature:@"MC0CFAsKO7cq2q7L5/FWe6ybVIQkwAwSAhUA2Q8GKsE309eugi/v3Kh1W3w3N8"
                             error:&error],
                   @"Expected invalid signature: %@", error);
}

- (void)testVerifyFileAtPathUsingED25519
{
    NSString *validSig = @"EIawm2YkDZ2gBfkEMF2+1VuuTeXnCGZOdnMdVgPPvDZioq7bvDayXqKkIIzSjKMmeFdcFJOHdnba5ZV60+gPBw==";

    NSError *error = nil;
    
    XCTAssertTrue([self checkFile:_testFile
                        withEdKey:_pubEdKey
                        signature:validSig
                            error:&error],
                  @"Expected valid signature: %@", error);

    XCTAssertFalse([self checkFile:_testFile
                         withEdKey:@"lol"
                         signature:validSig
                             error:&error],
                   @"Invalid pubkey: %@", error);

    XCTAssertFalse([self checkFile:_pubDSAKeyFile
                         withEdKey:_pubEdKey
                         signature:validSig
                             error:&error],
                   @"Wrong file checked: %@", error);

    XCTAssertFalse([self checkFile:_testFile
                         withEdKey:_pubEdKey
                         signature:@"wTcpXCgWoa4NrJpsfzS61FXJIbv963//12U2ef9xstzVOLPHYK2N4/ojgpDV5N1/NGG1uWMBgK+kEWp0Z5zMDQ=="
                             error:&error],
                   @"Expected wrong signature: %@", error);

    XCTAssertFalse([self checkFile:_testFile
                         withEdKey:_pubEdKey
                         signature:@"lol"
                             error:&error],
                   @"Invalid signature: %@", error);
}

- (BOOL)checkFile:(NSString *)aFile withDSAKey:(NSString *)pubKey signature:(NSString *)sigString error:(NSError * __autoreleasing *)error
{
    SUPublicKeys *pubKeys = [[SUPublicKeys alloc] initWithEd:nil dsa:pubKey];
    SUSignatureVerifier *v = [[SUSignatureVerifier alloc] initWithPublicKeys:pubKeys];

    SUSignatures *sig = [[SUSignatures alloc] initWithEd:nil
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
                                                     dsa:sigString
#endif
    ];

    return [v verifyFileAtPath:aFile signatures:sig verifierInformation:nil error:error];
}

static SUSignatures *_createSignatures(NSString *edString, NSString *dsaString)
{
#if !SPARKLE_BUILD_LEGACY_DSA_SUPPORT
    (void)dsaString;
#endif
    
    SUSignatures *sig = [[SUSignatures alloc] initWithEd:edString
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
                                                     dsa:dsaString
#endif
    ];
    
    return sig;
}

- (BOOL)checkFile:(NSString *)aFile withEdKey:(NSString *)pubKey signature:(NSString *)sigString error:(NSError * __autoreleasing *)error
{
    SUPublicKeys *pubKeys = [[SUPublicKeys alloc] initWithEd:pubKey
                                                         dsa:nil];
    
    SUSignatureVerifier *v = [[SUSignatureVerifier alloc] initWithPublicKeys:pubKeys];

    SUSignatures *sig = _createSignatures(sigString, nil);

    return [v verifyFileAtPath:aFile signatures:sig verifierInformation:nil error:error];
}

- (void)testVerifyFileWithBothKeys
{
    NSString *dsaKey = [NSString stringWithContentsOfFile:_pubDSAKeyFile encoding:NSASCIIStringEncoding error:nil];
    XCTAssertNotNil(dsaKey, @"Public key must be readable");

    SUPublicKeys *pubKeys = [[SUPublicKeys alloc] initWithEd:_pubEdKey dsa:dsaKey];
    SUSignatureVerifier *v = [[SUSignatureVerifier alloc] initWithPublicKeys:pubKeys];
    NSError *error = nil;

    XCTAssertFalse([v verifyFileAtPath:_testFile
                            signatures:_createSignatures(nil, nil) verifierInformation:nil error:&error],
                   @"Fail if no signatures are provided: %@", error);
    XCTAssertFalse([v verifyFileAtPath:_testFile
                            signatures:_createSignatures(@"lol", @"lol") verifierInformation:nil error:&error],
                   @"Fail if both signatures are invalid: %@", error);

    NSString *dsaSig = @"MCwCFCIHCIYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ==";
    NSString *wrongDSASig = @"MCwCFCIHCiYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ==";
    NSString *edSig = @"EIawm2YkDZ2gBfkEMF2+1VuuTeXnCGZOdnMdVgPPvDZioq7bvDayXqKkIIzSjKMmeFdcFJOHdnba5ZV60+gPBw==";
    NSString *wrongEdSig = @"wTcpXCgWoa4NrJpsfzS61FXJIbv963//12U2ef9xstzVOLPHYK2N4/ojgpDV5N1/NGG1uWMBgK+kEWp0Z5zMDQ==";

    XCTAssertFalse([v verifyFileAtPath:_testFile
                            signatures:_createSignatures(nil, dsaSig) verifierInformation:nil error:&error],
                  @"EdDSA signature must be present if app has EdDSA key: %@", error);
    
    XCTAssertTrue([v verifyFileAtPath:_testFile
                           signatures:_createSignatures(edSig, nil) verifierInformation:nil error:&error],
                   @"Allow just an EdDSA signature if that's all that's available: %@", error);

    XCTAssertFalse([v verifyFileAtPath:_testFile
                            signatures:_createSignatures(wrongEdSig, dsaSig) verifierInformation:nil error:&error],
                   @"Fail on a bad Ed25519 signature regardless: %@", error);
    XCTAssertTrue([v verifyFileAtPath:_testFile
                           signatures:_createSignatures(edSig, wrongDSASig) verifierInformation:nil error:&error],
                   @"Allow bad DSA signature if EdDSA signature is good: %@", error);

    XCTAssertFalse([v verifyFileAtPath:_testFile
                            signatures:_createSignatures(@"lol", dsaSig) verifierInformation:nil error:&error],
                   @"Fail if the Ed25519 signature is invalid: %@", error);
    
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
    XCTAssertFalse([v verifyFileAtPath:_testFile
                            signatures:_createSignatures(edSig, @"lol") verifierInformation:nil error:&error],
                   @"Fail if invalid DSA signature is used even if EdDSA signature is good: %@", error);
#else
    XCTAssertTrue([v verifyFileAtPath:_testFile
                           signatures:_createSignatures(edSig, @"lol") error:&error],
                   @"Allow invalid DSA signature if EdDSA signature is good: %@", error);
#endif

    XCTAssertTrue([v verifyFileAtPath:_testFile
                           signatures:_createSignatures(edSig, dsaSig) verifierInformation:nil error:&error],
                  @"Pass if both are valid: %@", error);
}

- (void)testVerifyFileWithWrongKey
{
    NSError *error = nil;
    
    NSString *dsaSig = @"MCwCFCIHCIYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ==";
    NSString *edSig = @"EIawm2YkDZ2gBfkEMF2+1VuuTeXnCGZOdnMdVgPPvDZioq7bvDayXqKkIIzSjKMmeFdcFJOHdnba5ZV60+gPBw==";
    
    NSString *dsaKey = [NSString stringWithContentsOfFile:_pubDSAKeyFile encoding:NSASCIIStringEncoding error:nil];
    XCTAssertNotNil(dsaKey, @"Public key must be readable");
    
    SUPublicKeys *dsaOnlyKeys = [[SUPublicKeys alloc] initWithEd:nil dsa:dsaKey];
    SUSignatureVerifier *dsaOnlyVerifier = [[SUSignatureVerifier alloc] initWithPublicKeys:dsaOnlyKeys];

    XCTAssertFalse([dsaOnlyVerifier verifyFileAtPath:_testFile
                                          signatures:_createSignatures(edSig, nil) verifierInformation:nil error:&error],
                   @"DSA cannot verify an Ed signature: %@", error);
    
    SUPublicKeys *edOnlyKeys = [[SUPublicKeys alloc] initWithEd:_pubEdKey
                                                            dsa:nil];
    SUSignatureVerifier *edOnlyVerifier = [[SUSignatureVerifier alloc] initWithPublicKeys:edOnlyKeys];

    {
        SUSignatures *signatures = _createSignatures(nil, dsaSig);
        XCTAssertFalse([edOnlyVerifier verifyFileAtPath:_testFile
                                             signatures:signatures
                                    verifierInformation:nil
                                                  error:&error],
                       @"Ed cannot verify an DSA signature: %@", error);
    }

}

- (void)testValidatePath
{
    NSString *dsaStr = [NSString stringWithContentsOfFile:_pubDSAKeyFile encoding:NSASCIIStringEncoding error:nil];
    XCTAssertNotNil(dsaStr);
    SUPublicKeys *pubkeys = [[SUPublicKeys alloc] initWithEd:nil dsa:dsaStr];
    XCTAssertNotNil(pubkeys);
    XCTAssertNotNil(pubkeys.dsaPubKey);

    SUSignatures *sig = _createSignatures(nil, @"MC0CFFMF3ha5kjvrJ9JTpTR8BenPN9QUAhUAzY06JRdtP17MJewxhK0twhvbKIE=");
    XCTAssertNotNil(sig);
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
    XCTAssertNotNil(sig.dsaSignature);
#endif

    NSError *error = nil;
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
    XCTAssertTrue([SUSignatureVerifier validatePath:_testFile withSignatures:sig withPublicKeys:pubkeys verifierInformation:nil error:&error], @"Expected valid signature: %@", error);
#else
    XCTAssertFalse([SUSignatureVerifier validatePath:_testFile withSignatures:sig withPublicKeys:pubkeys verifierInformation:nil error:&error], @"Expected verification to fail due to disabling DSA: %@", error);
#endif
}

@end
