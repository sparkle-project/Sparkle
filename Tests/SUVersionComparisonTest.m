//
//  SUVersionComparisonTest.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/15/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUStandardVersionComparator.h"
#import <XCTest/XCTest.h>

@interface SUVersionComparisonTestCase : XCTestCase {
}
@end

@implementation SUVersionComparisonTestCase

#define SUAssertOrder(comparator, a, b, c) XCTAssertTrue([comparator compareVersion:a toVersion:b] == c, @"b should be newer than a!")
#define SUAssertAscending(comparator, a, b) SUAssertOrder(comparator, a, b, NSOrderedAscending)
#define SUAssertDescending(comparator, a, b) SUAssertOrder(comparator, a, b, NSOrderedDescending)
#define SUAssertEqual(comparator, a, b) SUAssertOrder(comparator, a, b, NSOrderedSame)

- (void)testNumbers
{
    SUStandardVersionComparator *comparator = [[SUStandardVersionComparator alloc] init];
    
    SUAssertAscending(comparator, @"1.0", @"1.1");
    SUAssertEqual(comparator, @"1.0", @"1.0");
    SUAssertDescending(comparator, @"2.0", @"1.1");
    SUAssertDescending(comparator, @"0.1", @"0.0.1");
    //SUAssertDescending(comparator, @".1", @"0.0.1"); Known bug, but I'm not sure I care.
    SUAssertAscending(comparator, @"0.1", @"0.1.2");
    
    SUAssertEqual(comparator, @"1.0", @"1.0.0");
    SUAssertEqual(comparator, @"1.0.0", @"1.0");
}

- (void)testCommitSHAs
{
    SUStandardVersionComparator *comparator = [[SUStandardVersionComparator alloc] init];
    
    SUAssertAscending(comparator, @"1.5.5-335d3e2", @"1.5.6-b252311");
    SUAssertEqual(comparator, @"1.5.5-335d3e2", @"1.5.5-a655360");
    SUAssertDescending(comparator, @"1.5.6-b252311", @"1.5.5-335d3e2");
    
    SUAssertEqual(comparator, @"1.5-335d3e2", @"1.5.0-335d3e2");
    SUAssertEqual(comparator, @"1.5.0-335d3e2", @"1.5-335d3e2");
}

- (void)testPrereleases
{
    SUStandardVersionComparator *comparator = [[SUStandardVersionComparator alloc] init];
    
    SUAssertAscending(comparator, @"1.5.5", @"1.5.6a1");
    SUAssertAscending(comparator, @"1.1.0b1", @"1.1.0b2");
    SUAssertAscending(comparator, @"1.1.1b2", @"1.1.2b1");
    SUAssertAscending(comparator, @"1.1.1b2", @"1.1.2a1");
    SUAssertAscending(comparator, @"1.0a1", @"1.0b1");
    SUAssertAscending(comparator, @"1.0b1", @"1.0");
    SUAssertAscending(comparator, @"0.9", @"1.0a1");
    SUAssertAscending(comparator, @"1.0b", @"1.0b2");
    SUAssertAscending(comparator, @"1.0b10", @"1.0b11");
    SUAssertAscending(comparator, @"1.0b9", @"1.0b10");
    SUAssertAscending(comparator, @"1.0rc", @"1.0");
    SUAssertAscending(comparator, @"1.0b", @"1.0");
    SUAssertAscending(comparator, @"1.0pre1", @"1.0");
    
    SUAssertEqual(comparator, @"1.0pre1", @"1.0.0pre1");
    SUAssertEqual(comparator, @"1.0.0pre1", @"1.0pre1");
}

- (void)testVersionsWithBuildNumbers
{
    SUStandardVersionComparator *comparator = [[SUStandardVersionComparator alloc] init];
    
    SUAssertAscending(comparator, @"1.0 (1234)", @"1.0 (1235)");
    SUAssertAscending(comparator, @"1.0b1 (1234)", @"1.0 (1234)");
    SUAssertAscending(comparator, @"1.0b5 (1234)", @"1.0b5 (1235)");
    SUAssertAscending(comparator, @"1.0b5 (1234)", @"1.0.1b5 (1234)");
    SUAssertAscending(comparator, @"1.0.1b5 (1234)", @"1.0.1b6 (1234)");
    SUAssertAscending(comparator, @"2.0.0.2429", @"2.0.0.2430");
    SUAssertAscending(comparator, @"1.1.1.1818", @"2.0.0.2430");
    
    SUAssertAscending(comparator, @"3.3 (5847)", @"3.3.1b1 (5902)");
    
    SUAssertEqual(comparator, @"3.3 (5847)", @"3.3.0 (5847)");
    SUAssertEqual(comparator, @"3.3.0 (5847)", @"3.3 (5847)");
    SUAssertEqual(comparator, @"1.1.1.1818", @"1.1.1.1818.0");
    SUAssertEqual(comparator, @"1.1.1.1818.0", @"1.1.1.1818");
    SUAssertEqual(comparator, @"3.3b1 (5902)", @"3.3.0b1 (5902)");
    SUAssertEqual(comparator, @"3.3.0b1 (5902)", @"3.3b1 (5902)");
}

- (void)testWordsWithSpaceInFront
{
    // SUStandardVersionComparator *comparator = [[SUStandardVersionComparator alloc] init];
    
    //	SUAssertAscending(comparator, @"1.0 beta", @"1.0");
    //	SUAssertAscending(comparator, @"1.0  - beta", @"1.0");
    //	SUAssertAscending(comparator, @"1.0 alpha", @"1.0 beta");
    //	SUAssertEqual(comparator, @"1.0  - beta", @"1.0beta");
    //	SUAssertEqual(comparator, @"1.0  - beta", @"1.0 beta");
}

- (void)testVersionsWithReverseDateBasedNumbers
{
    SUStandardVersionComparator *comparator = [[SUStandardVersionComparator alloc] init];
    
    SUAssertAscending(comparator, @"201210251627", @"201211051041");
    
    SUAssertEqual(comparator, @"201210251627.0", @"201210251627");
    SUAssertEqual(comparator, @"201210251627", @"201210251627.0");
}

@end
