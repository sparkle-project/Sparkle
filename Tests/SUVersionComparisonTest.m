//
//  SUVersionComparisonTest.m
//  Sparkle
//
//  Created by Andy Matuschak on 4/15/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUVersionComparisonTest.h"
#import "SUStandardVersionComparator.h"

@interface SUCustomVersionComparator : NSObject <SUVersionComparison>
- (NSComparisonResult)compareVersion:(NSString *)versionA toVersion:(NSString *)versionB;
@end

@implementation SUCustomVersionComparator

-(NSComparisonResult)compareVersion:(NSString *)versionA toVersion:(NSString *)versionB
{
    id<SUVersionComparison> standardCompare = [SUStandardVersionComparator defaultComparator];
    NSArray *partsA = [versionA componentsSeparatedByString:@"-"];
    NSArray *partsB = [versionB componentsSeparatedByString:@"-"];
    
    if ([partsA count] > 0 && [partsB count] > 0) {
        NSComparisonResult res = [standardCompare compareVersion:[partsA objectAtIndex:0] toVersion:[partsB objectAtIndex:0]];
        if (res != NSOrderedSame) {
            return res;
        }
        if ([partsA count] > 1 && [partsB count] > 1) {
            BOOL equal = [[partsA objectAtIndex:1] isEqualToString:[partsB objectAtIndex:1]];
            
            if (equal) {
                return NSOrderedSame;
            } else {
                return NSOrderedAscending;
            }
        }
    }
    return [standardCompare compareVersion:versionA toVersion:versionB];
}

@end

@implementation SUVersionComparisonTest

#define SUAssertOrder(a,b,c) STAssertTrue([[SUStandardVersionComparator defaultComparator] compareVersion:a toVersion:b] == c, @"b should be newer than a!")
#define SUAssertAscending(a, b) SUAssertOrder(a,b,NSOrderedAscending)
#define SUAssertDescending(a, b) SUAssertOrder(a,b,NSOrderedDescending)
#define SUAssertEqual(a, b) SUAssertOrder(a,b,NSOrderedSame)

#define SUAssertOrderCustom(cmp,a,b,c) STAssertTrue([cmp compareVersion:a toVersion:b] == c, @"b should be newer than a!")
#define SUAssertAscendingCustom(cmp, a, b) SUAssertOrderCustom(cmp, a, b, NSOrderedAscending)

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
}

- (void)testVersionsWithBuildNumbers
{
	SUAssertAscending(@"1.0 (1234)", @"1.0 (1235)");
	SUAssertAscending(@"1.0b1 (1234)", @"1.0 (1234)");
	SUAssertAscending(@"1.0b5 (1234)", @"1.0b5 (1235)");
	SUAssertAscending(@"1.0b5 (1234)", @"1.0.1b5 (1234)");
	SUAssertAscending(@"1.0.1b5 (1234)", @"1.0.1b6 (1234)");
	
	SUAssertAscending(@"3.3 (5847)", @"3.3.1b1 (5902)");
}

- (void)testVersionsWithSignatures
{
    SUAssertAscending(@"0.8.0-20130609D", @"0.8.0-20130701D");
    SUAssertAscending(@"0.8.0-20130609", @"0.8.0-20130701");

    id <SUVersionComparison> customCompare = [[[SUCustomVersionComparator alloc] init] autorelease];

    SUAssertAscendingCustom(customCompare, @"0.8.0-20130701", @"0.8.0-fb123");
    SUAssertAscendingCustom(customCompare, @"0.8.0-20130701", @"0.8.0-4fb13");
    SUAssertAscendingCustom(customCompare, @"0.8.0-20130701", @"0.8.0-0fb13");
}

- (void)testWordsWithSpaceInFront
{
//	SUAssertAscending(@"1.0 beta", @"1.0");
//	SUAssertAscending(@"1.0  - beta", @"1.0");
//	SUAssertAscending(@"1.0 alpha", @"1.0 beta");
//	SUAssertEqual(@"1.0  - beta", @"1.0beta");
//	SUAssertEqual(@"1.0  - beta", @"1.0 beta");
}

- (void)testVersionsWithReverseDateBasedNumbers
{
    SUAssertAscending(@"201210251627", @"201211051041");
}

@end
