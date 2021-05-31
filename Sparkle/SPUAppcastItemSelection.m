//
//  SPUAppcastItemSelection.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/30/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import "SPUAppcastItemSelection.h"
#import "SUHost.h"
#import "SUAppcastItem.h"
#import "SUAppcastItem+Private.h"
#import "SPUUpdater.h"
#import "SPUUpdaterDelegate.h"
#import "SUStandardVersionComparator.h"
#import "SUVersionComparisonProtocol.h"
#import "SUConstants.h"


#include "AppKitPrevention.h"

// Returns the critical update version string if available, otherwise returns
// a result (in isCriticalWithoutVersion) if the update is critical (without a version specified)
static NSString * _Nullable SPUAppcastItemCriticalUpdateVersion(SUAppcastItem *appcastItem, BOOL *isCriticalWithoutVersion)
{
    NSDictionary *criticalUpdateDictionary = appcastItem.criticalUpdateDictionary;
    if (criticalUpdateDictionary == nil) {
        *isCriticalWithoutVersion = NO;
        return nil;
    }
    
    NSString *criticalVersion = criticalUpdateDictionary[SUAppcastAttributeVersion];
    if (criticalVersion == nil || ![criticalVersion isKindOfClass:[NSString class]]) {
        *isCriticalWithoutVersion = YES;
        return nil;
    }
    
    return criticalVersion;
}

// Given a host version, is this update version considered critical?
static BOOL SPUCriticalUpdateTest(id<SUVersionComparison> versionComparator, NSString *hostVersion, NSString *criticalVersion)
{
    return ([versionComparator compareVersion:hostVersion toVersion:criticalVersion] == NSOrderedAscending);
}

BOOL SPUAppcastItemIsCriticalWithComparator(SUAppcastItem *appcastItem, NSString *hostVersion, id<SUVersionComparison> versionComparator)
{
    BOOL isCriticalWithoutVersion = NO;
    NSString *criticalVersion = SPUAppcastItemCriticalUpdateVersion(appcastItem, &isCriticalWithoutVersion);
    if (criticalVersion == nil) {
        return isCriticalWithoutVersion;
    }
    
    return SPUCriticalUpdateTest(versionComparator, hostVersion, criticalVersion);
}

BOOL SPUAppcastItemIsCritical(SUAppcastItem *appcastItem, NSString *hostVersion, SPUUpdater *updater, id<SPUUpdaterDelegate> _Nullable updaterDelegate)
{
    BOOL isCriticalWithoutVersion = NO;
    NSString *criticalVersion = SPUAppcastItemCriticalUpdateVersion(appcastItem, &isCriticalWithoutVersion);
    if (criticalVersion == nil) {
        return isCriticalWithoutVersion;
    }
    
    id<SUVersionComparison> versionComparator = SPUVersionComparator(updater, updaterDelegate);
    return SPUCriticalUpdateTest(versionComparator, hostVersion, criticalVersion);
}

id<SUVersionComparison> SPUVersionComparator(SPUUpdater *updater, id<SPUUpdaterDelegate> _Nullable updaterDelegate)
{
    id<SUVersionComparison> comparator = nil;
    
    // Give the delegate a chance to provide a custom version comparator
    if ([updaterDelegate respondsToSelector:@selector((versionComparatorForUpdater:))]) {
        comparator = [updaterDelegate versionComparatorForUpdater:(id _Nonnull)updater];
    }
    
    // If we don't get a comparator from the delegate, use the default comparator
    if (comparator == nil) {
        comparator = [SUStandardVersionComparator defaultComparator];
    }
    
    return comparator;
}
