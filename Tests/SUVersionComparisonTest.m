//
//  SUVersionComparisonTest.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/15/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUVersionComparisonTest.h"
#import "SUStandardVersionComparator.h"

@implementation SUVersionComparisonTest

#define SUAssertOrder(a,b,c) STAssertTrue([[SUStandardVersionComparator defaultComparator] compareVersion:a toVersion:b] == c, @"b should be newer than a!")
#define SUAssertAscending(a, b) SUAssertOrder(a,b,NSOrderedAscending)
#define SUAssertDescending(a, b) SUAssertOrder(a,b,NSOrderedDescending)
#define SUAssertEqual(a, b) SUAssertOrder(a,b,NSOrderedSame)

- (void)testNumbers
{
	SUAssertAscending(@"1.0", @"1.1");
	SUAssertEqual(@"1.0", @"1.0");
	SUAssertDescending(@"2.0", @"1.1");
	SUAssertDescending(@"0.1", @"0.0.1");
	//SUAssertDescending(@".1", @"0.0.1"); Known bug, but I'm not sure I care.
	SUAssertAscending(@"0.1", @"0.1.2");
}

- (void)testPrereleases
{
	SUAssertAscending(@"1.0a1", @"1.0b1");
	SUAssertAscending(@"1.0b1", @"1.0");
	SUAssertAscending(@"0.9", @"1.0a1");
	SUAssertAscending(@"1.0b", @"1.0b2");
	SUAssertAscending(@"1.0b10", @"1.0b11");
	SUAssertAscending(@"1.0b9", @"1.0b10");
	SUAssertAscending(@"1.0rc", @"1.0");
	SUAssertAscending(@"1.0b", @"1.0");
	SUAssertAscending(@"1.0pre1", @"1.0");
	SUAssertAscending(@"1.0 beta", @"1.0");
	SUAssertAscending(@"1.0 alpha", @"1.0 beta");
}

@end
