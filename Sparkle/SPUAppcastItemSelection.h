//
//  SPUAppcastItemSelection.h
//  Sparkle
//
//  Created by Mayur Pawashe on 5/30/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

@class SUAppcastItem;
@class SUHost;
@class SPUUpdater;

@protocol SPUUpdaterDelegate;
@protocol SUVersionComparison;

NS_ASSUME_NONNULL_BEGIN

// Functions for querying if appcast item properties that depend on current host version

BOOL SPUAppcastItemIsCriticalWithComparator(SUAppcastItem *appcastItem, NSString *hostVersion, id<SUVersionComparison> versionComparator);

BOOL SPUAppcastItemIsCritical(SUAppcastItem *appcastItem, NSString *hostVersion, SPUUpdater *updater, id<SPUUpdaterDelegate> _Nullable updaterDelegate);

id<SUVersionComparison> SPUVersionComparator(SPUUpdater *updater, id<SPUUpdaterDelegate> _Nullable updaterDelegate);

BOOL SPUAppcastItemContainsCriticalTag(SUAppcastItem *appcastItem);

NS_ASSUME_NONNULL_END
