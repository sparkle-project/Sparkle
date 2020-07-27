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
        return;
    }

    NSString *expectedDestination = @"/tmp/sparklepkgtest.app";
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:expectedDestination error:nil];
    XCTAssertFalse([fm fileExistsAtPath:expectedDestination isDirectory:nil]);

    XCTestExpectation *done = [self expectationWithDescription:@"install finished"];

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *path = [bundle pathForResource:@"test" ofType:@"pkg"];
    XCTAssertNotNil(path);

    SUHost *host = [[SUHost alloc] initWithBundle:bundle];

    NSString *fileOperationToolPath = [bundle pathForResource:@""SPARKLE_FILEOP_TOOL_NAME ofType:@""];
    XCTAssertNotNil(fileOperationToolPath);
    
    NSError *installerError = nil;
    id<SUInstallerProtocol> installer = [SUInstaller installerForHost:host fileOperationToolPath:fileOperationToolPath updateDirectory:[path stringByDeletingLastPathComponent] error:&installerError];
    
    if (installer == nil) {
        XCTFail(@"Failed to retrieve installer: %@", installerError);
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *initialInstallationError = nil;
        if (![installer performInitialInstallation:&initialInstallationError]) {
            XCTFail(@"Failed to perform initial installation: %@", initialInstallationError);
        }
        
        NSError *finalInstallationError = nil;
        if (![installer performFinalInstallationProgressBlock:nil error:&finalInstallationError]) {
            XCTFail(@"Failed to perform final installation with underlying error = %@ ; error = %@", [finalInstallationError.userInfo objectForKey:NSUnderlyingErrorKey], finalInstallationError);
        }
        
        XCTAssertTrue([fm fileExistsAtPath:expectedDestination isDirectory:nil]);
        [done fulfill];
    });

    [self waitForExpectationsWithTimeout:40 handler:nil];
    [fm removeItemAtPath:expectedDestination error:nil];
}
#endif

@end
