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
#import "SPUInstallationType.h"
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

#if SPARKLE_BUILD_PACKAGE_SUPPORT
- (void)testInstallIfRoot
{
    uid_t uid = getuid();

    if (uid != 0) {
        NSLog(@"Test must be run as root: sudo xcodebuild -project Sparkle.xcodeproj -scheme Sparkle '-only-testing:Sparkle Unit Tests/SUInstallerTest/testInstallIfRoot' test");
        return;
    }

    NSString *expectedDestination = @"/tmp/sparklepkgtest.app";
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:expectedDestination error:nil];
    XCTAssertFalse([fm fileExistsAtPath:expectedDestination isDirectory:nil]);

    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSString *path = [bundle pathForResource:@"test" ofType:@"pkg"];
    XCTAssertNotNil(path);

    SUHost *host = [[SUHost alloc] initWithBundle:bundle];

    NSError *installerError = nil;
    // Note: we may not be using the "correct" home directory or user name (they will be root) but our test pkg does not have
    // pre/post install scripts so it doesn't matter
    id<SUInstallerProtocol> installer = [SUInstaller installerForHost:host expectedInstallationType:SPUInstallationTypeGuidedPackage updateDirectory:[path stringByDeletingLastPathComponent] homeDirectory:NSHomeDirectory() userName:NSUserName() error:&installerError];
    
    if (installer == nil) {
        XCTFail(@"Installer is nil with error: %@", installerError);
        return;
    }
    
    NSError *initialInstallError = nil;
    if (![installer performInitialInstallation:&initialInstallError]) {
        XCTFail(@"Initial Installation failed with error: %@", initialInstallError);
        return;
    }

    NSError *finalInstallError = nil;
    if (![installer performFinalInstallationProgressBlock:nil error:&finalInstallError]) {
        XCTFail(@"Final installation failed with error: %@", finalInstallError);
        return;
    }

    XCTAssertTrue([fm fileExistsAtPath:expectedDestination isDirectory:nil]);

    [fm removeItemAtPath:expectedDestination error:nil];
}
#endif

@end
