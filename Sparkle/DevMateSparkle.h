//
//  DevMateSparkle.h
//  Sparkle
//
//  Created by Dmytro Tretiakov on 10/1/14.
//
//

#ifndef Sparkle_DevMateSparkle_h
#define Sparkle_DevMateSparkle_h

#import <Cocoa/Cocoa.h>

// If you are using your own copy of Sparkle.framework just define
// USED_CUSTOM_SPARKLE_FRAMEWORK macro.
#ifndef USED_CUSTOM_SPARKLE_FRAMEWORK

#define SUUpdater                               DM_SUUpdater
#define SUUpdaterQueue                          DM_SUUpdaterQueue
#define SUAppcast                               DM_SUAppcast
#define SUAppcastItem                           DM_SUAppcastItem
#define SUUpdaterDelegate                       DM_SUUpdaterDelegate
#define SUUpdaterDelegate_DevMateInteraction    DM_SUUpdaterDelegate_DevMateInteraction
#define SUVersionComparison                     DM_SUVersionComparison
#define SUStandardVersionComparator             DM_SUStandardVersionComparator
#define SUVersionDisplay                        DM_SUVersionDisplay

#import <DevMateSparkle/SUExport.h>
#import <DevMateSparkle/SUUpdater.h>
#import <DevMateSparkle/SUUpdaterQueue.h>
#import <DevMateSparkle/SUAppcast.h>
#import <DevMateSparkle/SUAppcastItem.h>
#import <DevMateSparkle/SUVersionComparisonProtocol.h>
#import <DevMateSparkle/SUStandardVersionComparator.h>
#import <DevMateSparkle/SUVersionDisplayProtocol.h>
#import <DevMateSparkle/SUErrors.h>

#endif // USED_CUSTOM_SPARKLE_FRAMEWORK

#endif // Sparkle_DevMateSparkle_h
