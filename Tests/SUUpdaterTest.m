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

@interface SUUpdaterTest : XCTestCase <SUUpdaterDelegate>
@property (strong) NSOperationQueue *queue;
@property (strong) SUUpdater *updater;
@end

@implementation SUUpdaterTest
{
    NSOperationQueue *queue;
    SUUpdater *updater;
}
@synthesize queue;
@synthesize updater;

- (void)setUp
{
    [super setUp];
    self.queue = [[NSOperationQueue alloc] init];
    self.updater = [[SUUpdater alloc] init];
    updater.delegate = self;
}

- (void)tearDown
{
    self.updater = nil;
    self.queue = nil;
    [super tearDown];
}

- (NSString *)feedURLStringForUpdater:(SUUpdater *) __unused updater
{
    return @"";
}

- (void)testFeedURL
{
    [updater feedURL]; // this WON'T throw

    [queue addOperationWithBlock:^{
        XCTAssertTrue(![NSThread isMainThread]);
        @try {
            [updater feedURL];
            XCTFail(@"feedURL did not throw an exception when called on a secondary thread");
        }
        @catch (NSException *exception) {
            NSLog(@"%@", exception);
        }
    }];
    [queue waitUntilAllOperationsAreFinished];
}

- (void)setTestFeedURL
{
    [updater setFeedURL:[NSURL URLWithString:@""]]; // this WON'T throw

    [queue addOperationWithBlock:^{
        XCTAssertTrue(![NSThread isMainThread]);
        @try {
            [updater setFeedURL:[NSURL URLWithString:@""]];
            XCTFail(@"setFeedURL: did not throw an exception when called on a secondary thread");
        }
        @catch (NSException *exception) {
            NSLog(@"%@", exception);
        }
    }];
    [queue waitUntilAllOperationsAreFinished];
}

@end
