//
//  SPULocalCacheDirectoryTest.m
//  Sparkle
//
//  Copyright © 2026 Sparkle Project. All rights reserved.
//

#import "SPULocalCacheDirectory.h"
#import <XCTest/XCTest.h>

@interface SPULocalCacheDirectoryTest : XCTestCase
@end

@implementation SPULocalCacheDirectoryTest

- (NSString *)cacheIdentifierForBundleIdentifier:(NSString *)bundleIdentifier
{
    return SPUCacheIdentifierForBundleIdentifier(bundleIdentifier);
}

- (void)testNeutralizesPackageLikeBundleIdentifierExtensionsCaseInsensitively
{
    XCTAssertEqualObjects([self cacheIdentifierForBundleIdentifier:@"com.example.application.app"], @"com.example.application.app.sparkle");
    XCTAssertEqualObjects([self cacheIdentifierForBundleIdentifier:@"com.example.application.ApP"], @"com.example.application.ApP.sparkle");
    XCTAssertEqualObjects([self cacheIdentifierForBundleIdentifier:@"com.example.helper.service"], @"com.example.helper.service.sparkle");
    XCTAssertEqualObjects([self cacheIdentifierForBundleIdentifier:@"com.example.helper.SeRvIcE"], @"com.example.helper.SeRvIcE.sparkle");
}

- (void)testPreservesOrdinaryBundleIdentifiers
{
    XCTAssertEqualObjects([self cacheIdentifierForBundleIdentifier:@"com.example.application"], @"com.example.application");
    XCTAssertEqualObjects([self cacheIdentifierForBundleIdentifier:@"com.example.service.worker"], @"com.example.service.worker");
}

@end
