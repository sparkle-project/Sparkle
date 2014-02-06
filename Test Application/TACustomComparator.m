//
//  TACustomComparator.m
//  Sparkle
//
//  Created by Edward Rudd on 7/10/13.
//  Copyright (c) 2013 OutOfOrder.cc. All rights reserved.
//

#import "TACustomComparator.h"

#import "SUStandardVersionComparator.h"

@implementation TACustomComparator

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
