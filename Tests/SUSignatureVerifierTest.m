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

    NSError *error = nil;
    
    XCTAssertTrue([self checkFile:self.testFile
                       withDSAKey:pubKey
                        signature:validSig
                            error:&error],
                  @"Expected valid signature: %@", error);

    XCTAssertFalse([self checkFile:self.testFile
                        withDSAKey:@"lol"
                         signature:validSig
                             error:&error],
                   @"Invalid pubkey: %@", error);

    XCTAssertFalse([self checkFile:self.pubDSAKeyFile
                        withDSAKey:pubKey
                         signature:validSig
                             error:&error],
                   @"Wrong file checked: %@", error);

    XCTAssertFalse([self checkFile:self.testFile
                        withDSAKey:pubKey
                         signature:@"MCwCFCIHCiYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ=="
                             error:&error],
                   @"Expected invalid signature: %@", error);

    XCTAssertTrue([self checkFile:self.testFile
                       withDSAKey:pubKey
                        signature:@"MC0CFAsKO7cq2q7L5/FWe6ybVIQkwAwSAhUA2Q8GKsE309eugi/v3Kh1W3w3N8c="
                            error:&error],
                  @"Expected valid signature: %@", error);

    XCTAssertFalse([self checkFile:self.testFile
                        withDSAKey:pubKey
                         signature:@"MC0CFAsKO7cq2q7L5/FWe6ybVIQkwAwSAhUA2Q8GKsE309eugi/v3Kh1W3w3N8"
                             error:&error],
                   @"Expected invalid signature: %@", error);
}

- (void)testVerifyFileAtPathUsingED25519
{
    NSString *validSig = @"EIawm2YkDZ2gBfkEMF2+1VuuTeXnCGZOdnMdVgPPvDZioq7bvDayXqKkIIzSjKMmeFdcFJOHdnba5ZV60+gPBw==";

    NSError *error = nil;
    
    XCTAssertTrue([self checkFile:self.testFile
                        withEdKey:self.pubEdKey
                        signature:validSig
                            error:&error],
                  @"Expected valid signature: %@", error);

    XCTAssertFalse([self checkFile:self.testFile
                         withEdKey:@"lol"
                         signature:validSig
                             error:&error],
                   @"Invalid pubkey: %@", error);

    XCTAssertFalse([self checkFile:self.pubDSAKeyFile
                         withEdKey:self.pubEdKey
                         signature:validSig
                             error:&error],
                   @"Wrong file checked: %@", error);

    XCTAssertFalse([self checkFile:self.testFile
                         withEdKey:self.pubEdKey
                         signature:@"wTcpXCgWoa4NrJpsfzS61FXJIbv963//12U2ef9xstzVOLPHYK2N4/ojgpDV5N1/NGG1uWMBgK+kEWp0Z5zMDQ=="
                             error:&error],
                   @"Expected wrong signature: %@", error);

    XCTAssertFalse([self checkFile:self.testFile
                         withEdKey:self.pubEdKey
                         signature:@"lol"
                             error:&error],
                   @"Invalid signature: %@", error);
}

- (BOOL)checkFile:(NSString *)aFile withDSAKey:(NSString *)pubKey signature:(NSString *)sigString error:(NSError * __autoreleasing *)error
{
    SUPublicKeys *pubKeys = [[SUPublicKeys alloc] initWithDsa:pubKey ed:nil];
    SUSignatureVerifier *v = [[SUSignatureVerifier alloc] initWithPublicKeys:pubKeys];

    SUSignatures *sig = [[SUSignatures alloc] initWithDsa:sigString ed:nil];

    return [v verifyFileAtPath:aFile signatures:sig error:error];
}

- (BOOL)checkFile:(NSString *)aFile withEdKey:(NSString *)pubKey signature:(NSString *)sigString error:(NSError * __autoreleasing *)error
{
    SUPublicKeys *pubKeys = [[SUPublicKeys alloc] initWithDsa:nil ed:pubKey];
    SUSignatureVerifier *v = [[SUSignatureVerifier alloc] initWithPublicKeys:pubKeys];

    SUSignatures *sig = [[SUSignatures alloc] initWithDsa:nil ed:sigString];

    return [v verifyFileAtPath:aFile signatures:sig error:error];
}

- (void)testVerifyFileWithBothKeys
{
    NSString *dsaKey = [NSString stringWithContentsOfFile:self.pubDSAKeyFile encoding:NSASCIIStringEncoding error:nil];
    XCTAssertNotNil(dsaKey, @"Public key must be readable");

    SUPublicKeys *pubKeys = [[SUPublicKeys alloc] initWithDsa:dsaKey ed:self.pubEdKey];
    SUSignatureVerifier *v = [[SUSignatureVerifier alloc] initWithPublicKeys:pubKeys];
    NSError *error = nil;

    XCTAssertFalse([v verifyFileAtPath:self.testFile
                            signatures:[[SUSignatures alloc] initWithDsa:nil ed:nil] error:&error],
                   @"Fail if no signatures are provided: %@", error);
    XCTAssertFalse([v verifyFileAtPath:self.testFile
                            signatures:[[SUSignatures alloc] initWithDsa:@"lol" ed:@"lol"] error:&error],
                   @"Fail if both signatures are invalid: %@", error);

    NSString *dsaSig = @"MCwCFCIHCIYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ==";
    NSString *wrongDSASig = @"MCwCFCIHCiYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ==";
    NSString *edSig = @"EIawm2YkDZ2gBfkEMF2+1VuuTeXnCGZOdnMdVgPPvDZioq7bvDayXqKkIIzSjKMmeFdcFJOHdnba5ZV60+gPBw==";
    NSString *wrongEdSig = @"wTcpXCgWoa4NrJpsfzS61FXJIbv963//12U2ef9xstzVOLPHYK2N4/ojgpDV5N1/NGG1uWMBgK+kEWp0Z5zMDQ==";

    XCTAssertFalse([v verifyFileAtPath:self.testFile
                            signatures:[[SUSignatures alloc] initWithDsa:dsaSig ed:nil] error:&error],
                  @"EdDSA signature must be present if app has EdDSA key: %@", error);
    
    XCTAssertTrue([v verifyFileAtPath:self.testFile
                           signatures:[[SUSignatures alloc] initWithDsa:nil ed:edSig] error:&error],
                   @"Allow just an EdDSA signature if that's all that's available: %@", error);

    XCTAssertFalse([v verifyFileAtPath:self.testFile
                            signatures:[[SUSignatures alloc] initWithDsa:dsaSig ed:wrongEdSig] error:&error],
                   @"Fail on a bad Ed25519 signature regardless: %@", error);
    XCTAssertTrue([v verifyFileAtPath:self.testFile
                           signatures:[[SUSignatures alloc] initWithDsa:wrongDSASig ed:edSig] error:&error],
                   @"Allow bad DSA signature if EdDSA signature is good: %@", error);

    XCTAssertFalse([v verifyFileAtPath:self.testFile
                            signatures:[[SUSignatures alloc] initWithDsa:dsaSig ed:@"lol"] error:&error],
                   @"Fail if the Ed25519 signature is invalid: %@", error);
    XCTAssertFalse([v verifyFileAtPath:self.testFile
                            signatures:[[SUSignatures alloc] initWithDsa:@"lol" ed:edSig] error:&error],
                   @"Fail if invalid DSA signature is used even if EdDSA signature is good: %@", error);

    XCTAssertTrue([v verifyFileAtPath:self.testFile
                           signatures:[[SUSignatures alloc] initWithDsa:dsaSig ed:edSig] error:&error],
                  @"Pass if both are valid: %@", error);
}

- (void)testVerifyFileWithWrongKey
{
    NSString *dsaSig = @"MCwCFCIHCIYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ==";
    NSString *edSig = @"EIawm2YkDZ2gBfkEMF2+1VuuTeXnCGZOdnMdVgPPvDZioq7bvDayXqKkIIzSjKMmeFdcFJOHdnba5ZV60+gPBw==";

    NSString *dsaKey = [NSString stringWithContentsOfFile:self.pubDSAKeyFile encoding:NSASCIIStringEncoding error:nil];
    XCTAssertNotNil(dsaKey, @"Public key must be readable");

    SUPublicKeys *dsaOnlyKeys = [[SUPublicKeys alloc] initWithDsa:dsaKey ed:nil];
    SUSignatureVerifier *dsaOnlyVerifier = [[SUSignatureVerifier alloc] initWithPublicKeys:dsaOnlyKeys];

    NSError *error = nil;
    XCTAssertFalse([dsaOnlyVerifier verifyFileAtPath:self.testFile
                                          signatures:[[SUSignatures alloc] initWithDsa:nil ed:edSig] error:&error],
                   @"DSA cannot verify an Ed signature: %@", error);

    SUPublicKeys *edOnlyKeys = [[SUPublicKeys alloc] initWithDsa:nil ed:self.pubEdKey];
    SUSignatureVerifier *edOnlyVerifier = [[SUSignatureVerifier alloc] initWithPublicKeys:edOnlyKeys];

    XCTAssertFalse([edOnlyVerifier verifyFileAtPath:self.testFile
                                         signatures:[[SUSignatures alloc] initWithDsa:dsaSig ed:nil] error:&error],
                   @"Ed cannot verify an DSA signature: %@", error);

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

    NSError *error = nil;
    XCTAssertTrue([SUSignatureVerifier validatePath:self.testFile withSignatures:sig withPublicKeys:pubkeys error:&error], @"Expected valid signature: %@", error);
}

@end
