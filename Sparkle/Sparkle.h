//
//  Sparkle.h
//  Sparkle
//
//  Created by Andy Matuschak on 3/16/06. (Modified by CDHW on 23/12/07)
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#ifndef SPARKLE_H
#define SPARKLE_H

// This list should include the shared headers. It doesn't matter if some of them aren't shared (unless
// there are name-space collisions) so we can list all of them to start with:

#import "SUAppcast.h"
#import "SUAppcastItem.h"
#import "SUStandardVersionComparator.h"
#import "SPUUpdater.h"
#import "SPUUpdaterDelegate.h"
#import "SPUUpdaterSettings.h"
#import "SPUStandardUpdaterController.h"
#import "SUVersionComparisonProtocol.h"
#import "SUVersionDisplayProtocol.h"
#import "SUErrors.h"
#import "SPUUpdatePermissionRequest.h"
#import "SUUpdatePermissionResponse.h"
#import "SPUUserDriver.h"
#import "SPUStandardUserDriver.h"
#import "SPUStandardUserDriverDelegate.h"
#import "SPUUserDriverCoreComponent.h"
#import "SPUDownloadData.h"

#import "SUUpdater.h" // deprecated
#import "SUUpdaterDelegate.h" // deprecated

#endif
