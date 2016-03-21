//
//  SUUpdaterTest.m
//  Sparkle
//
//  Created by Jake Petroules on 2014-06-29.
//  Copyright (c) 2014 Sparkle Project. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "SUConstants.h"
#import "SUUpdater.h"
#import "SUStandardUserDriver.h"

// This user driver does nothing
@interface SUUselessUserDriver : NSObject <SUUserDriver>

@end

@implementation SUUselessUserDriver

- (void)showUpdateInProgress:(BOOL)__unused isUpdateInProgress {}

- (void)idleOnUpdateChecks:(BOOL)__unused shouldIdleOnUpdateChecks {}

- (void)startUpdateCheckTimerWithNextTimeInterval:(NSTimeInterval)__unused timeInterval reply:(void (^)(SUUpdateCheckTimerStatus))__unused reply {}

- (void)invalidateUpdateCheckTimer {}

- (void)requestUpdatePermissionWithSystemProfile:(NSArray *)__unused systemProfile reply:(void (^)(SUUpdatePermissionPromptResult *))__unused reply {}

- (void)showUserInitiatedUpdateCheckWithCompletion:(void (^)(SUUserInitiatedCheckStatus))__unused updateCheckStatusCompletion {}

- (void)dismissUserInitiatedUpdateCheck {}

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)__unused appcastItem allowsAutomaticUpdates:(BOOL)__unused allowsAutomaticUpdates alreadyDownloaded:(BOOL)alreadyDownloaded reply:(void (^)(SUUpdateAlertChoice))__unused reply {}

- (void)showUpdateNotFoundWithAcknowledgement:(void (^)(void))__unused acknowledgement {}

- (void)showUpdaterError:(NSError *)__unused error acknowledgement:(void (^)(void))__unused acknowledgement {}

- (void)showDownloadInitiatedWithCompletion:(void (^)(SUDownloadUpdateStatus))__unused downloadUpdateStatusCompletion {}

- (void)showDownloadDidReceiveResponse:(NSURLResponse *)__unused response {}

- (void)showDownloadDidReceiveDataOfLength:(NSUInteger)__unused length {}

- (void)showDownloadFinishedAndStartedExtractingUpdate {}

- (void)showExtractionReceivedProgress:(double)__unused progress {}

- (void)showExtractionFinishedAndReadyToInstallAndRelaunch:(void (^)(SUInstallUpdateStatus))__unused installUpdateHandler {}

- (void)showInstallingUpdate {}

- (void)dismissUpdateInstallation {}

@end

@interface SUUpdaterTest : XCTestCase <SUUpdaterDelegate>
@property (strong) NSOperationQueue *queue;
@property (strong) SUUpdater *updater;
@end

@implementation SUUpdaterTest

@synthesize queue;
@synthesize updater;

- (void)setUp
{
    [super setUp];
    self.queue = [[NSOperationQueue alloc] init];
    self.updater = [[SUUpdater alloc] initWithHostBundle:[NSBundle bundleForClass:[self class]] userDriver:[[SUUselessUserDriver alloc] init] delegate:self];
}

- (void)tearDown
{
    self.updater = nil;
    self.queue = nil;
    [super tearDown];
}

- (NSString *)feedURLStringForUpdater:(SUUpdater *) __unused updater
{
    return @"https://test.example.com";
}

- (void)testFeedURL
{
    [self.updater feedURL]; // this WON'T throw

    [self.queue addOperationWithBlock:^{
        XCTAssertTrue(![NSThread isMainThread]);
        @try {
            [self.updater feedURL];
            XCTFail(@"feedURL did not throw an exception when called on a secondary thread");
        }
        @catch (NSException *exception) {
            NSLog(@"%@", exception);
        }
    }];
    [self.queue waitUntilAllOperationsAreFinished];
}

- (void)testSetTestFeedURL
{
    [self.updater setFeedURL:[NSURL URLWithString:@""]]; // this WON'T throw

    [self.queue addOperationWithBlock:^{
        XCTAssertTrue(![NSThread isMainThread]);
        @try {
            [self.updater setFeedURL:[NSURL URLWithString:@""]];
            XCTFail(@"setFeedURL: did not throw an exception when called on a secondary thread");
        }
        @catch (NSException *exception) {
            NSLog(@"%@", exception);
        }
    }];
    [self.queue waitUntilAllOperationsAreFinished];
}

@end
