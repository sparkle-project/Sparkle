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
@property (strong) SPUUpdater *updater;
@end

@implementation SUUpdaterTest

@synthesize updater;

- (void)setUp
{
    [super setUp];
    
    // We really want a useless / not really functional user driver so we will pass nil here
    // For real world applications we should pass a valid user driver which is why this is not a nullable parameter
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wnonnull"
    self.updater = [[SPUUpdater alloc] initWithHostBundle:[NSBundle bundleForClass:[self class]] userDriver:nil delegate:self];
#pragma clang diagnostic pop
    
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
