//
//  SUInstallerTest.m
//  Sparkle
//
//  Created by Kornel on 24/04/2015.
//  Copyright (c) 2015 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <XCTest/XCTest.h>
#import "SUHost.h"
#import "SUInstaller.h"
#import "SUInstallerProtocol.h"
#import "SUStandardVersionComparator.h"
#import <unistd.h>

@interface SUInstallerTest : XCTestCase

@end

@implementation SUInstallerTest

- (void)setUp
{
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown
{
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}

#if __clang_major__ >= 6
- (void)testInstallIfRoot
{
    uid_t uid = getuid();

    if (uid) {
        NSLog(@"Test must be run as root: sudo xctest -XCTest SUInstallerTest 'Sparkle Unit Tests.xctest'");
        return; // or just comment this line out and enter password when the auth. prompt comes up
    }

    NSString *expectedDestination = @"/tmp/sparklepkgtest.app";
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:expectedDestination error:nil];
    XCTAssertFalse([fm fileExistsAtPath:expectedDestination isDirectory:nil]);

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *path = [bundle pathForResource:@"test.sparkle_guided" ofType:@"pkg"];
    XCTAssertNotNil(path);

    SUHost *host = [[SUHost alloc] initWithBundle:bundle];
    
    NSError *installerError = nil;
    id<SUInstaller> installer = [SUInstaller installerForHost:host updateDirectory:[path stringByDeletingLastPathComponent] versionComparator:[SUStandardVersionComparator standardVersionComparator] error:&installerError];
    
    if (installer == nil) {
        XCTFail(@"Installer is nil with error: %@", installerError);
        return;
    }
    
    NSError *firstStageError = nil;
    if (![installer performFirstStage:&firstStageError]) {
        XCTFail(@"First Stage failed with error: %@", firstStageError);
        return;
    }
    
    NSError *secondStageError = nil;
    if (![installer performSecondStageAllowingUI:YES error:&secondStageError]) {
        XCTFail(@"Second Stage failed with error: %@", secondStageError);
        return;
    }
    
    NSError *thirdStageError = nil;
    if (![installer performThirdStage:&thirdStageError]) {
        XCTFail(@"Third Stage failed with error: %@", thirdStageError);
        return;
    }
    
    [installer cleanup];
    
    XCTAssertTrue([fm fileExistsAtPath:expectedDestination isDirectory:nil]);
    
    [fm removeItemAtPath:expectedDestination error:nil];
}
#endif

@end
