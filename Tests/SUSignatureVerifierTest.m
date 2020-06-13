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
@property NSString *testFile, *pubDSAKeyFile, *pubEdKey;
@end

@implementation SUSignatureVerifierTest
@synthesize testFile, pubDSAKeyFile, pubEdKey;

- (void)setUp
{
    [super setUp];

    self.testFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"signed-test-file" ofType:@"txt"];
    self.pubDSAKeyFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"test-pubkey" ofType:@"pem"];
    self.pubEdKey = @"rhHib+w769W2/6/t+oM1ZxgjBB93BfBKMLO0Qo1etQs=";
}

- (void)testVerifyFileAtPathUsingDSA
{
    NSString *pubKey = [NSString stringWithContentsOfFile:self.pubDSAKeyFile encoding:NSASCIIStringEncoding error:nil];
    XCTAssertNotNil(pubKey, @"Public key must be readable");

    NSString *validSig = @"MCwCFCIHCIYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ==";

    XCTAssertTrue([self checkFile:self.testFile
                       withDSAKey:pubKey
                        signature:validSig],
                  @"Expected valid signature");

    XCTAssertFalse([self checkFile:self.testFile
                        withDSAKey:@"lol"
                         signature:validSig],
                   @"Invalid pubkey");

    XCTAssertFalse([self checkFile:self.pubDSAKeyFile
                        withDSAKey:pubKey
                         signature:validSig],
                   @"Wrong file checked");

    XCTAssertFalse([self checkFile:self.testFile
                        withDSAKey:pubKey
                         signature:@"MCwCFCIHCiYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ=="],
                   @"Expected invalid signature");

    XCTAssertTrue([self checkFile:self.testFile
                       withDSAKey:pubKey
                        signature:@"MC0CFAsKO7cq2q7L5/FWe6ybVIQkwAwSAhUA2Q8GKsE309eugi/v3Kh1W3w3N8c="],
                  @"Expected valid signature");

    XCTAssertFalse([self checkFile:self.testFile
                        withDSAKey:pubKey
                         signature:@"MC0CFAsKO7cq2q7L5/FWe6ybVIQkwAwSAhUA2Q8GKsE309eugi/v3Kh1W3w3N8"],
                   @"Expected invalid signature");
}

- (void)testVerifyFileAtPathUsingED25519
{
    NSString *validSig = @"EIawm2YkDZ2gBfkEMF2+1VuuTeXnCGZOdnMdVgPPvDZioq7bvDayXqKkIIzSjKMmeFdcFJOHdnba5ZV60+gPBw==";

    XCTAssertTrue([self checkFile:self.testFile
                        withEdKey:self.pubEdKey
                        signature:validSig],
                  @"Expected valid signature");

    XCTAssertFalse([self checkFile:self.testFile
                         withEdKey:@"lol"
                         signature:validSig],
                   @"Invalid pubkey");

    XCTAssertFalse([self checkFile:self.pubDSAKeyFile
                         withEdKey:self.pubEdKey
                         signature:validSig],
                   @"Wrong file checked");

    XCTAssertFalse([self checkFile:self.testFile
                         withEdKey:self.pubEdKey
                         signature:@"wTcpXCgWoa4NrJpsfzS61FXJIbv963//12U2ef9xstzVOLPHYK2N4/ojgpDV5N1/NGG1uWMBgK+kEWp0Z5zMDQ=="],
                   @"Expected wrong signature");

    XCTAssertFalse([self checkFile:self.testFile
                         withEdKey:self.pubEdKey
                         signature:@"lol"],
                   @"Invalid signature");
}

- (BOOL)checkFile:(NSString *)aFile withDSAKey:(NSString *)pubKey signature:(NSString *)sigString
{
    SUPublicKeys *pubKeys = [[SUPublicKeys alloc] initWithDsa:pubKey ed:nil];
    SUSignatureVerifier *v = [[SUSignatureVerifier alloc] initWithPublicKeys:pubKeys];

    SUSignatures *sig = [[SUSignatures alloc] initWithDsa:sigString ed:nil];

    return [v verifyFileAtPath:aFile signatures:sig];
}

- (BOOL)checkFile:(NSString *)aFile withEdKey:(NSString *)pubKey signature:(NSString *)sigString
{
    SUPublicKeys *pubKeys = [[SUPublicKeys alloc] initWithDsa:nil ed:pubKey];
    SUSignatureVerifier *v = [[SUSignatureVerifier alloc] initWithPublicKeys:pubKeys];

    SUSignatures *sig = [[SUSignatures alloc] initWithDsa:nil ed:sigString];

    return [v verifyFileAtPath:aFile signatures:sig];
}

- (void)testVerifyFileWithBothKeys
{
    NSString *dsaKey = [NSString stringWithContentsOfFile:self.pubDSAKeyFile encoding:NSASCIIStringEncoding error:nil];
    XCTAssertNotNil(dsaKey, @"Public key must be readable");

    SUPublicKeys *pubKeys = [[SUPublicKeys alloc] initWithDsa:dsaKey ed:self.pubEdKey];
    SUSignatureVerifier *v = [[SUSignatureVerifier alloc] initWithPublicKeys:pubKeys];

    XCTAssertFalse([v verifyFileAtPath:self.testFile
                            signatures:[[SUSignatures alloc] initWithDsa:nil ed:nil]],
                   @"Fail if no signatures are provided");
    XCTAssertFalse([v verifyFileAtPath:self.testFile
                            signatures:[[SUSignatures alloc] initWithDsa:@"lol" ed:@"lol"]],
                   @"Fail if both signatures are invalid");

    NSString *dsaSig = @"MCwCFCIHCIYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ==";
    NSString *wrongDSASig = @"MCwCFCIHCiYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ==";
    NSString *edSig = @"EIawm2YkDZ2gBfkEMF2+1VuuTeXnCGZOdnMdVgPPvDZioq7bvDayXqKkIIzSjKMmeFdcFJOHdnba5ZV60+gPBw==";
    NSString *wrongEdSig = @"wTcpXCgWoa4NrJpsfzS61FXJIbv963//12U2ef9xstzVOLPHYK2N4/ojgpDV5N1/NGG1uWMBgK+kEWp0Z5zMDQ==";

    XCTAssertTrue([v verifyFileAtPath:self.testFile
                           signatures:[[SUSignatures alloc] initWithDsa:dsaSig ed:nil]],
                  @"Allow just a DSA signature if that's all that's available");
    XCTAssertFalse([v verifyFileAtPath:self.testFile
                            signatures:[[SUSignatures alloc] initWithDsa:nil ed:edSig]],
                   @"Require the DSA signature to match because there's a DSA public key");

    XCTAssertFalse([v verifyFileAtPath:self.testFile
                            signatures:[[SUSignatures alloc] initWithDsa:dsaSig ed:wrongEdSig]],
                   @"Fail on a bad Ed25519 signature regardless");
    XCTAssertFalse([v verifyFileAtPath:self.testFile
                            signatures:[[SUSignatures alloc] initWithDsa:wrongDSASig ed:edSig]],
                   @"Fail on a bad DSA signature if provided");

    XCTAssertFalse([v verifyFileAtPath:self.testFile
                            signatures:[[SUSignatures alloc] initWithDsa:dsaSig ed:@"lol"]],
                   @"Fail if the Ed25519 signature is invalid.");
    XCTAssertFalse([v verifyFileAtPath:self.testFile
                           signatures:[[SUSignatures alloc] initWithDsa:@"lol" ed:edSig]],
                   @"Fail if the DSA signature is invalid.");

    XCTAssertTrue([v verifyFileAtPath:self.testFile
                           signatures:[[SUSignatures alloc] initWithDsa:dsaSig ed:edSig]],
                  @"Pass if both are valid");
}

- (void)testVerifyFileWithWrongKey
{
    NSString *dsaSig = @"MCwCFCIHCIYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ==";
    NSString *edSig = @"EIawm2YkDZ2gBfkEMF2+1VuuTeXnCGZOdnMdVgPPvDZioq7bvDayXqKkIIzSjKMmeFdcFJOHdnba5ZV60+gPBw==";

    NSString *dsaKey = [NSString stringWithContentsOfFile:self.pubDSAKeyFile encoding:NSASCIIStringEncoding error:nil];
    XCTAssertNotNil(dsaKey, @"Public key must be readable");

    SUPublicKeys *dsaOnlyKeys = [[SUPublicKeys alloc] initWithDsa:dsaKey ed:nil];
    SUSignatureVerifier *dsaOnlyVerifier = [[SUSignatureVerifier alloc] initWithPublicKeys:dsaOnlyKeys];

    XCTAssertFalse([dsaOnlyVerifier verifyFileAtPath:self.testFile
                                          signatures:[[SUSignatures alloc] initWithDsa:nil ed:edSig]],
                   @"DSA cannot verify an Ed signature");

    SUPublicKeys *edOnlyKeys = [[SUPublicKeys alloc] initWithDsa:nil ed:self.pubEdKey];
    SUSignatureVerifier *edOnlyVerifier = [[SUSignatureVerifier alloc] initWithPublicKeys:edOnlyKeys];

    XCTAssertFalse([edOnlyVerifier verifyFileAtPath:self.testFile
                                         signatures:[[SUSignatures alloc] initWithDsa:dsaSig ed:nil]],
                   @"Ed cannot verify an DSA signature");

}

- (void)testValidatePath
{
    NSString *dsaStr = [NSString stringWithContentsOfFile:self.pubDSAKeyFile encoding:NSASCIIStringEncoding error:nil];
    XCTAssertNotNil(dsaStr);
    SUPublicKeys *pubkeys = [[SUPublicKeys alloc] initWithDsa:dsaStr ed:nil];
    XCTAssertNotNil(pubkeys);
    XCTAssertNotNil(pubkeys.dsaPubKey);

    SUSignatures *sig = [[SUSignatures alloc] initWithDsa:@"MC0CFFMF3ha5kjvrJ9JTpTR8BenPN9QUAhUAzY06JRdtP17MJewxhK0twhvbKIE=" ed:nil];
    XCTAssertNotNil(sig);
    XCTAssertNotNil(sig.dsaSignature);

    XCTAssertTrue([SUSignatureVerifier validatePath:self.testFile withSignatures:sig withPublicKeys:pubkeys], @"Expected valid signature");
}

@end
