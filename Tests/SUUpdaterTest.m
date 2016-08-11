//
//  SUUpdaterTest.m
//  Sparkle
//
//  Created by Jake Petroules on 2014-06-29.
//  Copyright (c) 2014 Sparkle Project. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "SUConstants.h"
#import "SPUUpdater.h"
#import "SPUStandardUserDriver.h"
#import "SUUpdaterDelegate.h"

// This user driver does nothing
@interface SUUselessUserDriver : NSObject <SPUUserDriver>

@end

@implementation SUUselessUserDriver

- (void)showCanCheckForUpdates:(BOOL)__unused canCheckForUpdates {}

- (void)idleOnUpdateChecks:(BOOL)__unused shouldIdleOnUpdateChecks {}

- (void)startUpdateCheckTimerWithNextTimeInterval:(NSTimeInterval)__unused timeInterval reply:(void (^)(SUUpdateCheckTimerStatus))__unused reply {}

- (void)invalidateUpdateCheckTimer {}

- (void)requestUpdatePermissionWithSystemProfile:(NSArray *)__unused systemProfile reply:(void (^)(SPUUpdatePermission *))__unused reply {}

- (void)showUserInitiatedUpdateCheckWithCompletion:(void (^)(SUUserInitiatedCheckStatus))__unused updateCheckStatusCompletion {}

- (void)dismissUserInitiatedUpdateCheck {}

- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)__unused appcastItem reply:(void (^)(SUUpdateAlertChoice))__unused reply {}

- (void)showDownloadedUpdateFoundWithAppcastItem:(SUAppcastItem *)__unused appcastItem reply:(void (^)(SUUpdateAlertChoice))__unused reply {}

- (void)showResumableUpdateFoundWithAppcastItem:(SUAppcastItem *)__unused appcastItem reply:(void (^)(SUInstallUpdateStatus))__unused reply {}

- (void)showUpdateReleaseNotesWithData:(NSData *)__unused releaseNotesData textEncodingName:(NSString * _Nullable)__unused textEncodingName MIMEType:(NSString * _Nullable)__unused MIMEType {}

- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)__unused error {}

- (void)showUpdateNotFoundWithAcknowledgement:(void (^)(void))__unused acknowledgement {}

- (void)showUpdaterError:(NSError *)__unused error acknowledgement:(void (^)(void))__unused acknowledgement {}

- (void)showDownloadInitiatedWithCompletion:(void (^)(SUDownloadUpdateStatus))__unused downloadUpdateStatusCompletion {}

- (void)showDownloadDidReceiveExpectedContentLength:(NSUInteger)__unused expectedContentLength {}

- (void)showDownloadDidReceiveDataOfLength:(NSUInteger)__unused length {}

- (void)showDownloadDidStartExtractingUpdate {}

- (void)showExtractionReceivedProgress:(double)__unused progress {}

- (void)showReadyToInstallAndRelaunch:(void (^)(SUInstallUpdateStatus))__unused installUpdateHandler {}

- (void)showInstallingUpdate {}

- (void)showUpdateInstallationDidFinish {}

- (void)dismissUpdateInstallation {}

- (void)terminateApplication {}

@end

@interface SUUpdaterTest : XCTestCase <SUUpdaterDelegate>
@property (strong) SPUUpdater *updater;
@end

@implementation SUUpdaterTest

@synthesize updater;

- (void)setUp
{
    [super setUp];
    self.updater = [[SPUUpdater alloc] initWithHostBundle:[NSBundle bundleForClass:[self class]] userDriver:[[SUUselessUserDriver alloc] init] delegate:self];
    
    NSError *error = nil;
    if (![self.updater startUpdater:&error]) {
        NSLog(@"Updater error: %@", error);
        abort();
    }
}

- (void)tearDown
{
    self.updater = nil;
    [super tearDown];
}

- (NSString *)feedURLStringForUpdater:(id)__unused updater
{
    return @"https://test.example.com";
}

- (void)testFeedURL
{
    [self.updater feedURL]; // this WON'T throw
}

- (void)testSetTestFeedURL
{
    NSURL *emptyURL = [NSURL URLWithString:@""];
    XCTAssertNotNil(emptyURL);
    [self.updater setFeedURL:emptyURL]; // this WON'T throw
}

@end
