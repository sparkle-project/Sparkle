//
//  SUBinaryDeltaTest.m
//  Sparkle
//
//  Created by Jake Petroules on 2014-08-22.
//  Copyright (c) 2014 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>
#import "SUBinaryDeltaCommon.h"

@interface SUBinaryDeltaTest : XCTestCase

@end

@implementation SUBinaryDeltaTest

- (void)testTemporaryFilename
{
    NSString *tmp1 = temporaryFilename(@"Sparkle");
    NSString *tmp2 = temporaryFilename(@"Sparkle");
    NSLog(@"Temporary filenames: %@, %@", tmp1, tmp2);
    XCTAssertNotEqualObjects(tmp1, tmp2);
    XCTAssert(YES, @"Pass");
}

@end
