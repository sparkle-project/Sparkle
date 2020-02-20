//
//  SUDSAVerifierTest.m
//  Sparkle
//
//  Created by Kornel on 25/07/2014.
//  Copyright (c) 2014 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "SUSignatureVerifier.h"
#import "SUSignatures.h"

@interface SUDSAVerifierTest : XCTestCase
@property NSString *testFile, *pubKeyFile;
@end

@implementation SUDSAVerifierTest
@synthesize testFile, pubKeyFile;

- (void)setUp
{
    [super setUp];

    self.testFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"signed-test-file" ofType:@"txt"];
    self.pubKeyFile = [[NSBundle bundleForClass:[self class]] pathForResource:@"test-pubkey" ofType:@"pem"];
}

- (void)testVerifyFileAtPath
{
    NSString *pubKey = [NSString stringWithContentsOfFile:self.pubKeyFile encoding:NSASCIIStringEncoding error:nil];
    XCTAssertNotNil(pubKey, @"Public key must be readable");

    NSString *validSig = @"MCwCFCIHCIYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ==";

    XCTAssertTrue([self checkFile:self.testFile
                       withPubKey:pubKey
                        signature:validSig],
                  @"Expected valid signature");

    XCTAssertFalse([self checkFile:self.testFile
                        withPubKey:@"lol"
                         signature:validSig],
                   @"Invalid pubkey");

    XCTAssertFalse([self checkFile:self.pubKeyFile
                        withPubKey:pubKey
                         signature:validSig],
                   @"Wrong file checked");

    XCTAssertFalse([self checkFile:self.testFile
                        withPubKey:pubKey
                         signature:@"MCwCFCIHCiYYkfZavNzTitTW5tlRp/k5AhQ40poFytqcVhIYdCxQznaXeJPJDQ=="],
                   @"Expected invalid signature");

    XCTAssertTrue([self checkFile:self.testFile
                       withPubKey:pubKey
                        signature:@"MC0CFAsKO7cq2q7L5/FWe6ybVIQkwAwSAhUA2Q8GKsE309eugi/v3Kh1W3w3N8c="],
                  @"Expected valid signature");

    XCTAssertFalse([self checkFile:self.testFile
                        withPubKey:pubKey
                         signature:@"MC0CFAsKO7cq2q7L5/FWe6ybVIQkwAwSAhUA2Q8GKsE309eugi/v3Kh1W3w3N8"],
                   @"Expected invalid signature");
}

- (BOOL)checkFile:(NSString *)aFile withPubKey:(NSString *)pubKey signature:(NSString *)sigString
{
    SUPublicKeys *pubKeys = [[SUPublicKeys alloc] initWithDsa:pubKey ed:nil];
    SUSignatureVerifier *v = [[SUSignatureVerifier alloc] initWithPublicKeys:pubKeys];

    SUSignatures *sig = [[SUSignatures alloc] initWithDsa:sigString ed:nil];

    return [v verifyFileAtPath:aFile signatures:sig];
}

- (void)testValidatePath
{
    NSString *dsaStr = [NSString stringWithContentsOfFile:self.pubKeyFile encoding:NSASCIIStringEncoding error:nil];
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
