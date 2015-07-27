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

#if __clang_major__ >= 6
@interface SUPipedUnarchiverTest : XCTestCase <SUUnarchiverDelegate>

@property (nonatomic, strong) XCTestExpectation *unarchived;
@property (nonatomic, assign) BOOL result;

@end

@implementation SUPipedUnarchiverTest

@synthesize unarchived;
@synthesize result;

- (void)setUp
{
    [super setUp];
    self.unarchived = [self expectationWithDescription:@"unarchived"];
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

- (void)unarchiver:(SUUnarchiver *)__unused unarchiver extractedProgress:(double)__unused progress
{
}

- (void)unarchiverDidFail:(SUUnarchiver *)__unused unarchiver
{
    self.result = NO;
    [self.unarchived fulfill];
}

- (void)unarchiverDidFinish:(SUUnarchiver *)__unused unarchiver
{
    self.result = YES;
    [self.unarchived fulfill];
}

- (void)testZipExtract
{
    NSString *originalArchivePath = [[NSBundle bundleForClass:[self class]] pathForResource:@"test archive" ofType:@"zip"];
    NSString *tempDestDir = NSTemporaryDirectory();
    NSString *tempArchivePath = [[tempDestDir stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]] stringByAppendingPathExtension:@"zip"];

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

    XCTAssertTrue(self.result);
    XCTAssertTrue([fm fileExistsAtPath:testFile isDirectory:nil]);
}

@end
#endif
