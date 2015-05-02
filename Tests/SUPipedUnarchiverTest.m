//
//  SUPipedUnarchiverTest.m
//  Sparkle
//
//  Created by Kornel on 23/04/2015.
//  Copyright (c) 2015 Sparkle Project. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <XCTest/XCTest.h>
#import "SUUnarchiver.h"
#import "SUPipedUnarchiver.h"

@interface SUPipedUnarchiverTest : XCTestCase<SUUnarchiverDelegate>
@end

@implementation SUPipedUnarchiverTest {
    XCTestExpectation *unarchived;
    BOOL result;
}

- (void)setUp {
    [super setUp];
    unarchived = [self expectationWithDescription:@"unarchived"];
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void) unarchiver:(SUUnarchiver *)unarchiver extractedProgress:(double)_unused {
}

- (void) unarchiverDidFail:(SUUnarchiver *)_unused {
    result = NO;
    [unarchived fulfill];
}

- (void) unarchiverDidFinish:(SUUnarchiver *)_unused {
    result = YES;
    [unarchived fulfill];
}

- (void)testZipExtract {
    NSString *originalArchivePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"test archive" ofType:@"zip"];
    NSString *tempDestDir = NSTemporaryDirectory();
    NSString *tempArchivePath = [[tempDestDir stringByAppendingPathComponent:[NSUUID UUID].UUIDString] stringByAppendingPathExtension:@"zip"];

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *testFile = [tempDestDir stringByAppendingPathComponent:@"extracted file.txt"];
    [fm removeItemAtPath:testFile error:nil];

    XCTAssertFalse([fm fileExistsAtPath:testFile isDirectory:nil]);
    XCTAssertTrue([fm copyItemAtPath:originalArchivePath toPath:tempArchivePath error:nil]);

    SUUnarchiver *unarc = [SUUnarchiver unarchiverForPath:tempArchivePath updatingHostBundlePath:nil];

    XCTAssertTrue([unarc isKindOfClass:[SUPipedUnarchiver class]]);

    unarc.delegate = self;
    [unarc start];

    [self waitForExpectationsWithTimeout:5.0 handler:nil];

    XCTAssertTrue(result);
    XCTAssertTrue([fm fileExistsAtPath:testFile isDirectory:nil]);
}

@end
