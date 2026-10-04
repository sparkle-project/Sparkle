//
//  SPUUpdateDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/15/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SPUDownloadedUpdate;
@class SUHost;
@protocol SPUUserDriver, SPUUpdaterDelegate;

// The driver's cycle has ended. resumableLocalUpdate reflects the local state (a downloaded-but-not-installed
// update) that should be passed back in on the next cycle, if any.
typedef void (^SPUUpdateDriverCompletion)(BOOL shouldResetImpatientCheckDate, SPUDownloadedUpdate * _Nullable resumableLocalUpdate, NSError * _Nullable error);

typedef NS_ENUM(NSUInteger, SPUUpdateDriverInstallMode) {
    // The driver only probes for update information and never shows anything or downloads/installs
    // (eg: -checkForUpdateInformation)
    SPUUpdateDriverInstallModeNone,

    // The driver may silently download and stage/install an update without asking first.
    // If an update needs the user's attention before proceeding (eg: it's a major upgrade,
    // informational-only, critical, or requires authorization), the driver escalates to
    // SPUUpdateDriverInstallModeShowingUI in the same cycle rather than proceeding silently.
    SPUUpdateDriverInstallModeAutomatic,

    // The driver presents UI via the user driver and asks before downloading/installing.
    SPUUpdateDriverInstallModeShowingUI,
};

// This class drives an update check cycle: querying the appcast, downloading, extracting,
// installing, and presenting UI as needed, according to its install mode.
SPU_OBJC_DIRECT_MEMBERS @interface SPUUpdateDriver : NSObject

- (instancetype)initWithHost:(SUHost *)host applicationBundle:(NSBundle *)applicationBundle updater:(id)updater userDriver:(nullable id <SPUUserDriver>)userDriver updaterDelegate:(nullable id <SPUUpdaterDelegate>)updaterDelegate userInitiated:(BOOL)userInitiated installMode:(SPUUpdateDriverInstallMode)installMode;

// Only meaningful for a driver constructed with SPUUpdateDriverInstallModeAutomatic.
// Must be set (along with impatientUpdateCheckInterval) before starting a check.
@property (nonatomic, copy) NSDate *lastImpatientCheckedDate;
@property (nonatomic) NSTimeInterval impatientUpdateCheckInterval;

- (void)setCompletionHandler:(SPUUpdateDriverCompletion)completionBlock;

- (void)setUpdateShownHandler:(void (^)(void))updateShownHandler;

- (void)setUpdateWillInstallHandler:(void (^)(void))updateWillInstallHandler;

// Checks for updates, resuming resumableLocalUpdate (a downloaded-but-not-installed update) if one
// was passed back from a prior cycle's completion handler. The driver also probes on its own for an
// update that an external installer job (eg: from another instance of the updater)
// may already be staging or installing; if it finds one, that global state
// takes priority over resumableLocalUpdate.
- (void)checkForUpdatesAtAppcastURL:(NSURL *)appcastURL withUserAgent:(NSString *)userAgent httpHeaders:(nullable NSDictionary *)httpHeaders resumingLocalUpdate:(nullable SPUDownloadedUpdate *)resumableLocalUpdate;

@property (nonatomic, readonly) BOOL showingUpdate;

// This should be invoked on the update driver to finish the update driver's work
- (void)abortUpdateWithError:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END
