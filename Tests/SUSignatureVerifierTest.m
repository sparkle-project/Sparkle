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

#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
- (void)testVerifyFileAtPathUsingDSA
{
    NSString *pubKey = [NSString stringWithContentsOfFile:_pubDSAKeyFile encoding:NSASCIIStringEncoding error:nil];
    XCTAssertNotNil(pubKey, @"Public key must be readable");

    NSString *validSig = @"MCwCFCIHCIYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ==";

    NSError *error = nil;
    
    XCTAssertTrue([self checkFile:_testFile
                       withDSAKey:pubKey
                        signature:validSig
                            error:&error],
                  @"Expected valid signature: %@", error);

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

    XCTAssertTrue([self checkFile:_testFile
                       withDSAKey:pubKey
                        signature:@"MC0CFAsKO7cq2q7L5/FWe6ybVIQkwAwSAhUA2Q8GKsE309eugi/v3Kh1W3w3N8c="
                            error:&error],
                  @"Expected valid signature: %@", error);

    XCTAssertFalse([self checkFile:_testFile
                        withDSAKey:pubKey
                         signature:@"MC0CFAsKO7cq2q7L5/FWe6ybVIQkwAwSAhUA2Q8GKsE309eugi/v3Kh1W3w3N8"
                             error:&error],
                   @"Expected invalid signature: %@", error);
}
#endif

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

#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
- (BOOL)checkFile:(NSString *)aFile withDSAKey:(NSString *)pubKey signature:(NSString *)sigString error:(NSError * __autoreleasing *)error
{
    SUPublicKeys *pubKeys = [[SUPublicKeys alloc] initWithEd:nil dsa:pubKey];
    SUSignatureVerifier *v = [[SUSignatureVerifier alloc] initWithPublicKeys:pubKeys];

    SUSignatures *sig = [[SUSignatures alloc] initWithEd:nil dsa:sigString];

    return [v verifyFileAtPath:aFile signatures:sig error:error];
}
#endif

- (BOOL)checkFile:(NSString *)aFile withEdKey:(NSString *)pubKey signature:(NSString *)sigString error:(NSError * __autoreleasing *)error
{
    SUPublicKeys *pubKeys = [[SUPublicKeys alloc] initWithEd:pubKey
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
                                                         dsa:nil
#endif
    ];
    
    SUSignatureVerifier *v = [[SUSignatureVerifier alloc] initWithPublicKeys:pubKeys];

    SUSignatures *sig = [[SUSignatures alloc] initWithEd:sigString
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
                                                     dsa:nil
#endif
    ];

    return [v verifyFileAtPath:aFile signatures:sig error:error];
}

#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
- (void)testVerifyFileWithBothKeys
{
    NSString *dsaKey = [NSString stringWithContentsOfFile:_pubDSAKeyFile encoding:NSASCIIStringEncoding error:nil];
    XCTAssertNotNil(dsaKey, @"Public key must be readable");

    SUPublicKeys *pubKeys = [[SUPublicKeys alloc] initWithEd:_pubEdKey dsa:dsaKey];
    SUSignatureVerifier *v = [[SUSignatureVerifier alloc] initWithPublicKeys:pubKeys];
    NSError *error = nil;

    XCTAssertFalse([v verifyFileAtPath:_testFile
                            signatures:[[SUSignatures alloc] initWithEd:nil dsa:nil] error:&error],
                   @"Fail if no signatures are provided: %@", error);
    XCTAssertFalse([v verifyFileAtPath:_testFile
                            signatures:[[SUSignatures alloc] initWithEd:@"lol" dsa:@"lol"] error:&error],
                   @"Fail if both signatures are invalid: %@", error);

    NSString *dsaSig = @"MCwCFCIHCIYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ==";
    NSString *wrongDSASig = @"MCwCFCIHCiYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ==";
    NSString *edSig = @"EIawm2YkDZ2gBfkEMF2+1VuuTeXnCGZOdnMdVgPPvDZioq7bvDayXqKkIIzSjKMmeFdcFJOHdnba5ZV60+gPBw==";
    NSString *wrongEdSig = @"wTcpXCgWoa4NrJpsfzS61FXJIbv963//12U2ef9xstzVOLPHYK2N4/ojgpDV5N1/NGG1uWMBgK+kEWp0Z5zMDQ==";

    XCTAssertFalse([v verifyFileAtPath:_testFile
                            signatures:[[SUSignatures alloc] initWithEd:nil dsa:dsaSig] error:&error],
                  @"EdDSA signature must be present if app has EdDSA key: %@", error);
    
    XCTAssertTrue([v verifyFileAtPath:_testFile
                           signatures:[[SUSignatures alloc] initWithEd:edSig dsa:nil] error:&error],
                   @"Allow just an EdDSA signature if that's all that's available: %@", error);

    XCTAssertFalse([v verifyFileAtPath:_testFile
                            signatures:[[SUSignatures alloc] initWithEd:wrongEdSig dsa:dsaSig] error:&error],
                   @"Fail on a bad Ed25519 signature regardless: %@", error);
    XCTAssertTrue([v verifyFileAtPath:_testFile
                           signatures:[[SUSignatures alloc] initWithEd:edSig dsa:wrongDSASig] error:&error],
                   @"Allow bad DSA signature if EdDSA signature is good: %@", error);

    XCTAssertFalse([v verifyFileAtPath:_testFile
                            signatures:[[SUSignatures alloc] initWithEd:@"lol" dsa:dsaSig] error:&error],
                   @"Fail if the Ed25519 signature is invalid: %@", error);
    XCTAssertFalse([v verifyFileAtPath:_testFile
                            signatures:[[SUSignatures alloc] initWithEd:edSig dsa:@"lol"] error:&error],
                   @"Fail if invalid DSA signature is used even if EdDSA signature is good: %@", error);

    XCTAssertTrue([v verifyFileAtPath:_testFile
                           signatures:[[SUSignatures alloc] initWithEd:edSig dsa:dsaSig] error:&error],
                  @"Pass if both are valid: %@", error);
}
#endif

- (void)testVerifyFileWithWrongKey
{
    NSError *error = nil;
    
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
    NSString *dsaSig = @"MCwCFCIHCIYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ==";
    NSString *edSig = @"EIawm2YkDZ2gBfkEMF2+1VuuTeXnCGZOdnMdVgPPvDZioq7bvDayXqKkIIzSjKMmeFdcFJOHdnba5ZV60+gPBw==";
    
    NSString *dsaKey = [NSString stringWithContentsOfFile:_pubDSAKeyFile encoding:NSASCIIStringEncoding error:nil];
    XCTAssertNotNil(dsaKey, @"Public key must be readable");
    
    SUPublicKeys *dsaOnlyKeys = [[SUPublicKeys alloc] initWithEd:nil dsa:dsaKey];
    SUSignatureVerifier *dsaOnlyVerifier = [[SUSignatureVerifier alloc] initWithPublicKeys:dsaOnlyKeys];

    XCTAssertFalse([dsaOnlyVerifier verifyFileAtPath:_testFile
                                          signatures:[[SUSignatures alloc] initWithEd:edSig dsa:nil] error:&error],
                   @"DSA cannot verify an Ed signature: %@", error);
#endif
    
    SUPublicKeys *edOnlyKeys = [[SUPublicKeys alloc] initWithEd:_pubEdKey
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
                                                            dsa:nil
#endif
    ];
    SUSignatureVerifier *edOnlyVerifier = [[SUSignatureVerifier alloc] initWithPublicKeys:edOnlyKeys];

    {
        SUSignatures *signatures = [[SUSignatures alloc] initWithEd:nil
#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
                                                                dsa:dsaSig
#endif
        ];
        XCTAssertFalse([edOnlyVerifier verifyFileAtPath:_testFile
                                             signatures:signatures
                                                  error:&error],
                       @"Ed cannot verify an DSA signature: %@", error);
    }

}

#if SPARKLE_BUILD_LEGACY_DSA_SUPPORT
- (void)testValidatePath
{
    NSString *dsaStr = [NSString stringWithContentsOfFile:_pubDSAKeyFile encoding:NSASCIIStringEncoding error:nil];
    XCTAssertNotNil(dsaStr);
    SUPublicKeys *pubkeys = [[SUPublicKeys alloc] initWithEd:nil dsa:dsaStr];
    XCTAssertNotNil(pubkeys);
    XCTAssertNotNil(pubkeys.dsaPubKey);

    SUSignatures *sig = [[SUSignatures alloc] initWithEd:nil dsa:@"MC0CFFMF3ha5kjvrJ9JTpTR8BenPN9QUAhUAzY06JRdtP17MJewxhK0twhvbKIE="];
    XCTAssertNotNil(sig);
    XCTAssertNotNil(sig.dsaSignature);

    NSError *error = nil;
    XCTAssertTrue([SUSignatureVerifier validatePath:_testFile withSignatures:sig withPublicKeys:pubkeys error:&error], @"Expected valid signature: %@", error);
}
#endif

@end
