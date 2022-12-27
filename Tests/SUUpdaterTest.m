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
#import "SPUUpdaterDelegate.h"

@interface SUUpdaterTest : XCTestCase <SPUUpdaterDelegate>
@end

@implementation SUUpdaterTest
{
    SPUUpdater *_updater;
}

- (void)setUp
{
    [super setUp];
    
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    // We really want a useless / not really functional user driver so we will pass nil here
    // For real world applications we should pass a valid user driver which is why this is not a nullable parameter
    _updater = [[SPUUpdater alloc] initWithHostBundle:bundle applicationBundle:bundle userDriver:nil delegate:self];
#pragma clang diagnostic pop
    
    NSError *error = nil;
    if (![_updater startUpdater:&error]) {
        NSLog(@"Updater error: %@", error);
        abort();
    }
    
    [_updater clearFeedURLFromUserDefaults];
}

- (void)tearDown
{
    _updater = nil;
    [super tearDown];
}

- (NSString *)feedURLStringForUpdater:(id)__unused updater
{
    return @"https://test.example.com";
}

- (void)testFeedURL
{
    [_updater feedURL]; // this WON'T throw
}

- (void)testSetTestFeedURL
{
    NSURL *emptyURL = [NSURL URLWithString:@""];
    XCTAssertNotNil(emptyURL);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [_updater setFeedURL:emptyURL]; // this WON'T throw
#pragma clang diagnostic pop
}

@end
