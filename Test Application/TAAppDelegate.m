//
//  TAAppDelegate.m
//  Sparkle
//
//  Created by Edward Rudd on 7/10/13.
//  Copyright (c) 2013 OutOfOrder.cc. All rights reserved.
//

#import "TAAppDelegate.h"
#import "SUUpdater.h"
#import "TACustomComparator.h"

@implementation TAAppDelegate

- (id<SUVersionComparison>)versionComparatorForUpdater:(SUUpdater *)updater
{
    return [[[TACustomComparator alloc] init] autorelease];
}

@end
