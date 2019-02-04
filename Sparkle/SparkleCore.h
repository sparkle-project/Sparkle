//
//  SparkleCore.h
//  Sparkle
//
//  Created by Mayur Pawashe on 8/20/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

// Copied mostly from Sparkle.h

#ifndef SPARKLE_CORE_H
#define SPARKLE_CORE_H

// This list should include the shared headers. It doesn't matter if some of them aren't shared (unless
// there are name-space collisions) so we can list all of them to start with:

#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUStandardVersionComparator.h"
#import "SPUUpdater.h"
#import "SPUUpdaterDelegate.h"
#import "SPUUpdaterSettings.h"
#import <Sparkle/SUVersionComparisonProtocol.h>
#import <Sparkle/SUErrors.h>
#import <Sparkle/SPUUpdatePermissionRequest.h>
#import <Sparkle/SUUpdatePermissionResponse.h>
#import <Sparkle/SPUUserDriver.h>
#import <Sparkle/SPUUserDriverCoreComponent.h>
#import <Sparkle/SPUDownloadData.h>

#endif
