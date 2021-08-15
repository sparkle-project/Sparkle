//
//  SPUUpdaterDelegate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 8/12/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#if __has_feature(modules)
#if __has_warning("-Watimport-in-framework-header")
#pragma clang diagnostic ignored "-Watimport-in-framework-header"
#endif
@import Foundation;
#else
#import <Foundation/Foundation.h>
#endif
#import <Sparkle/SUExport.h>

@protocol SUVersionComparison;
@class SPUUpdater, SUAppcast, SUAppcastItem;

NS_ASSUME_NONNULL_BEGIN

// -----------------------------------------------------------------------------
// SUUpdater Notifications for events that might be interesting to more than just the delegate
// The updater will be the notification object
// -----------------------------------------------------------------------------
SU_EXPORT extern NSString *const SUUpdaterDidFinishLoadingAppCastNotification;
SU_EXPORT extern NSString *const SUUpdaterDidFindValidUpdateNotification;
SU_EXPORT extern NSString *const SUUpdaterDidNotFindUpdateNotification;
SU_EXPORT extern NSString *const SUUpdaterWillRestartNotification;
#define SUUpdaterWillRelaunchApplicationNotification SUUpdaterWillRestartNotification;
#define SUUpdaterWillInstallUpdateNotification SUUpdaterWillRestartNotification;

// Key for the SUAppcastItem object in the SUUpdaterDidFindValidUpdateNotification userInfo
SU_EXPORT extern NSString *const SUUpdaterAppcastItemNotificationKey;
// Key for the SUAppcast object in the SUUpdaterDidFinishLoadingAppCastNotification userInfo
SU_EXPORT extern NSString *const SUUpdaterAppcastNotificationKey;

// -----------------------------------------------------------------------------
//    System Profile Keys
// -----------------------------------------------------------------------------

SU_EXPORT extern NSString *const SUSystemProfilerApplicationNameKey;
SU_EXPORT extern NSString *const SUSystemProfilerApplicationVersionKey;
SU_EXPORT extern NSString *const SUSystemProfilerCPU64bitKey;
SU_EXPORT extern NSString *const SUSystemProfilerCPUCountKey;
SU_EXPORT extern NSString *const SUSystemProfilerCPUFrequencyKey;
SU_EXPORT extern NSString *const SUSystemProfilerCPUTypeKey;
SU_EXPORT extern NSString *const SUSystemProfilerCPUSubtypeKey;
SU_EXPORT extern NSString *const SUSystemProfilerHardwareModelKey;
SU_EXPORT extern NSString *const SUSystemProfilerMemoryKey;
SU_EXPORT extern NSString *const SUSystemProfilerOperatingSystemVersionKey;
SU_EXPORT extern NSString *const SUSystemProfilerPreferredLanguageKey;

// -----------------------------------------------------------------------------
//	SPUUpdater Delegate:
// -----------------------------------------------------------------------------

typedef NS_ENUM(NSInteger, SPUUpdateCheck)
{
    SPUUpdateCheckUserInitiated = 0,
    SPUUpdateCheckBackgroundScheduled = 1
};

/**
 Provides delegation methods to control the behavior of an `SPUUpdater` object.
 */
@protocol SPUUpdaterDelegate <NSObject>
@optional

/**
 Returns whether to allow Sparkle to pop up.
 
 For example, this may be used to prevent Sparkle from interrupting a setup assistant.
 Alternatively, you may want to consider starting the updater after eg: the setup assistant finishes
 
 @param updater The updater instance.
 @return @c YES if the updater may check for updates otherwise @c NO
 */
- (BOOL)updaterMayCheckForUpdates:(SPUUpdater *)updater;

/**
 Returns the set of Sparkle channels the updater is allowed to find new updates from.
 
 An appcast item can specify a channel the update is posted to. Without specifying a channel, the appcast item is posted to the default channel.
 For instance:
 ```
 <item>
    <sparkle:version>2.0 Beta 1</sparkle:version>
    <sparkle:channel>beta</sparkle:channel>
 </item>
 ```
 
 This example posts an update to the @c beta channel, so only updaters that are allowed to use the @c beta channel can find this update.
 
 If the @c <sparkle:channel> element is not present, the update item is posted to the default channel and can be found by any updater.
 
 You can pick any name you'd like for the channel. The valid characters for channel names are letters, numbers, dashes, underscores, and periods.
 
 Note to use this feature, all app versions that your users may update from in your feed must use a version of Sparkle that supports this feature.
 This feature was added in Sparkle 2.
 
 @return The set of channel names the updater is allowed to find new updates in. An empty set is the default behavior,
         which means the updater will only look for updates in the default channel.
 */
- (NSSet<NSString *> *)allowedChannelsForUpdater:(SPUUpdater *)updater;

/**
 Returns a custom appcast URL.
 
 Override this to dynamically specify the feed URL.
 
 @param updater The updater instance.
 @return An appcast feed URL to check for new updates in. Return @c nil for the default behavior and if you don't want to be delegated this task.
 */
- (nullable NSString *)feedURLStringForUpdater:(SPUUpdater *)updater;

/**
 Returns additional parameters to append to the appcast URL's query string.
 
 This is potentially based on whether or not Sparkle will also be sending along the system profile.
 
 @param updater The updater instance.
 @param sendingProfile Whether the system profile will also be sent.
 
 @return An array of dictionaries with keys: `key`, `value`, `displayKey`, `displayValue`, the latter two being specifically for display to the user.
 */
- (NSArray<NSDictionary<NSString *, NSString *> *> *)feedParametersForUpdater:(SPUUpdater *)updater sendingSystemProfile:(BOOL)sendingProfile;


/**
 Returns whether Sparkle should prompt the user about automatic update checks.
 
 Use this to override the default behavior.
 
 @param updater The updater instance.
 @return @c YES if the updater should prompt for permission to check for updates, otherwise @c NO
 */
- (BOOL)updaterShouldPromptForPermissionToCheckForUpdates:(SPUUpdater *)updater;

/**
 Returns an allowed list of system profile keys to be appended to the appcast URL's query string.

 By default all keys will be included. This method allows overriding which keys should only be allowed.

 @param updater The updater instance.

 @return An array of system profile keys to include in the appcast URL's query string. Elements must be one of the `SUSystemProfiler*Key` constants. Return @c nil for the default behavior and if you don't want to be delegated this task.
 */
- (nullable NSArray<NSString *> *)allowedSystemProfileKeysForUpdater:(SPUUpdater *)updater;

/**
 Called after Sparkle has downloaded the appcast from the remote server.
 
 Implement this if you want to do some special handling with the appcast once it finishes loading.
 
 @param updater The updater instance.
 @param appcast The appcast that was downloaded from the remote server.
 */
- (void)updater:(SPUUpdater *)updater didFinishLoadingAppcast:(SUAppcast *)appcast;

/**
 Called when a new valid update is found by the update driver.
 
 @param updater The updater instance.
 @param item The appcast item corresponding to the update that is proposed to be installed.
 */
- (void)updater:(SPUUpdater *)updater didFindValidUpdate:(SUAppcastItem *)item;

/**
 Called when a valid new update is not found.
 
 There are various reasons a new update is unavailable and can't be installed.
 
 The userInfo dictionary on the error is populated with three keys:
 - `SPULatestAppcastItemFoundKey`: if available, this may provide the latest `SUAppcastItem` that was found. This will be @c nil if it's unavailable.
 - `SPUNoUpdateFoundReasonKey`: This will provide the `SPUNoUpdateFoundReason`.
 For example the reason could be because the latest version in the feed requires a newer OS version or could be because the user is already on the latest version.
 - `SPUNoUpdateFoundUserInitiatedKey`: A boolean that indicates if a new update was not found when the user intitiated an update check manually.
 
 @param updater The updater instance.
 @param error An error containing information on why a new valid update was not found
 */
- (void)updaterDidNotFindUpdate:(SPUUpdater *)updater error:(NSError *)error;

/**
 Called when a valid new update is not found.
 
 If more information is needed on why an update was not found, use `-[SPUUpdaterDelegate updaterDidNotFindUpdate:error:]` instead.
 
 @param updater The updater instance.
 */
- (void)updaterDidNotFindUpdate:(SPUUpdater *)updater;

/**
 Returns the item in the appcast corresponding to the update that should be installed.
 
 Please consider using or migrating to other supported features before adopting this method.
 Specifically:
 - If you want to filter out certain tagged updates (like beta updates), consider `-[SPUUpdaterDelegate allowedChannelsForUpdater:]` instead.
 - If you want to treat certain updates as informational-only, consider supplying @c <sparkle:informationalUpdate> with a set of affected versions users are updating from.
 
 If you're using special logic or extensions in your appcast, implement this to use your own logic for finding a valid update, if any, in the given appcast.
 
 Do not base your logic by filtering out items with a minimum or maximum OS version or minimum autoupdate version
 because Sparkle already has logic for determining whether or not those items should be filtered out.
 
 Also do not return a non-top level item from the appcast such as a delta item. Delta items will be ignored.
 Sparkle picks the delta item from your selection if the appropriate one is available.
 
 This method will not be invoked with an appcast that has zero items. Pick the best item from the appcast.
 If an item is available that has the same version as the application or bundle to update, do not pick an item that is worse than that version.
 
 This method may be called multiple times for different selections and filters. This method should be efficient.
 
 Return `+[SUAppcastItem emptyAppcastItem]` if no appcast item is valid.
 
 Return @c nil if you don't want to be delegated this task and want to let Sparkle handle picking the best valid update.
 
 @param appcast The appcast that was downloaded from the remote server.
 @param updater The updater instance.
 @return The best valid appcast item.
 */
- (nullable SUAppcastItem *)bestValidUpdateInAppcast:(SUAppcast *)appcast forUpdater:(SPUUpdater *)updater;

/**
 Called when an update is skipped by the user.
 
 @param updater The updater instance.
 @param item The appcast item corresponding to the update that the user skipped.
 */
- (void)updater:(SPUUpdater *)updater userDidSkipThisVersion:(SUAppcastItem *)item;

/**
 Returns whether the release notes (if available) should be downloaded after an update is found and shown.
 
 This is specifically for the @c <releaseNotesLink> element in the appcast item.
 
 @param updater The updater instance.
 
 @return @c YES to download and show the release notes if available, otherwise @c NO. The default behavior is @c YES.
 */
- (BOOL)updaterShouldDownloadReleaseNotes:(SPUUpdater *)updater;

/**
 Called immediately before downloading the specified update.
 
 @param updater The updater instance.
 @param item The appcast item corresponding to the update that is proposed to be downloaded.
 @param request The mutable URL request that will be used to download the update.
 */
- (void)updater:(SPUUpdater *)updater willDownloadUpdate:(SUAppcastItem *)item withRequest:(NSMutableURLRequest *)request;

/**
 Called immediately after succesfull download of the specified update.
 
 @param updater The SUUpdater instance.
 @param item The appcast item corresponding to the update that has been downloaded.
 */
- (void)updater:(SPUUpdater *)updater didDownloadUpdate:(SUAppcastItem *)item;

/**
 Called after the specified update failed to download.
 
 @param updater The updater instance.
 @param item The appcast item corresponding to the update that failed to download.
 @param error The error generated by the failed download.
 */
- (void)updater:(SPUUpdater *)updater failedToDownloadUpdate:(SUAppcastItem *)item error:(NSError *)error;

/**
 Called when the user clicks the cancel button while and update is being downloaded.
 
 @param updater The updater instance.
 */
- (void)userDidCancelDownload:(SPUUpdater *)updater;

/**
 Called immediately before extracting the specified downloaded update.
 
 @param updater The SUUpdater instance.
 @param item The appcast item corresponding to the update that is proposed to be extracted.
 */
- (void)updater:(SPUUpdater *)updater willExtractUpdate:(SUAppcastItem *)item;

/**
 Called immediately after extracting the specified downloaded update.
 
 @param updater The SUUpdater instance.
 @param item The appcast item corresponding to the update that has been extracted.
 */
- (void)updater:(SPUUpdater *)updater didExtractUpdate:(SUAppcastItem *)item;

/**
 Called immediately before installing the specified update.
 
 @param updater The updater instance.
 @param item The appcast item corresponding to the update that is proposed to be installed.
 */
- (void)updater:(SPUUpdater *)updater willInstallUpdate:(SUAppcastItem *)item;

/**
 Returns whether the relaunch should be delayed in order to perform other tasks.
 
 This is not called if the user didn't relaunch on the previous update,
 in that case it will immediately restart.
 
 This may also not be called if the application is not going to relaunch after it terminates.
 
 @param updater The updater instance.
 @param item The appcast item corresponding to the update that is proposed to be installed.
 @param installHandler The install handler that must be completed before continuing with the relaunch.
 
 @return @c YES to delay the relaunch until @p installHandler is invoked.
 */
- (BOOL)updater:(SPUUpdater *)updater shouldPostponeRelaunchForUpdate:(SUAppcastItem *)item untilInvokingBlock:(void (^)(void))installHandler;

/**
 Returns whether the application should be relaunched at all.
 
 Some apps @b cannot be relaunched under certain circumstances.
 This method can be used to explicitly prevent a relaunch.
 
 @param updater The updater instance.
 @return @c YES if the updater should be relaunched, otherwise @c NO if it shouldn't.
 */
- (BOOL)updaterShouldRelaunchApplication:(SPUUpdater *)updater;

/**
 Called immediately before relaunching.
 
 @param updater The updater instance.
 */
- (void)updaterWillRelaunchApplication:(SPUUpdater *)updater;

/**
 Returns an object that compares version numbers to determine their arithmetic relation to each other.
 
 This method allows you to provide a custom version comparator.
 If you don't implement this method or return @c nil,
 the standard version comparator will be used.
 
 Note that the standard version comparator may be used during installation for preventing a downgrade,
 even if you provide a custom comparator here.
 
 @param updater The updater instance.
 @return The custom version comparator or @c nil if you don't want to be delegated this task.
 */
- (nullable id<SUVersionComparison>)versionComparatorForUpdater:(SPUUpdater *)updater;

/**
 Called when a background update will be scheduled after a delay.
 
 Automatic update checks need to be enabled for this to trigger.
 
 @param delay The delay in seconds until the next scheduled update will occur.
 
 @param updater The updater instance.
 */
- (void)updater:(SPUUpdater *)updater willScheduleUpdateCheckAfterDelay:(NSTimeInterval)delay;

/**
 Called when no update checks will be scheduled in the future.
 
 This may later change if automatic update checks become enabled.
 
 @param updater The updater instance.
 */
- (void)updaterWillNotScheduleUpdateCheck:(SPUUpdater *)updater;

/**
 Returns whether or not the updater should allow interaction from the installer
 
 Use this to override the default behavior which is to allow interaction with the installer.
 
 If interaction is allowed, then an authorization prompt may show up to the user if they do
 not curently have sufficient privileges to perform the installation of the new update.
 The installer may also show UI and progress when interaction is allowed.
 
 On the other hand, if interaction is not allowed, then an installation may fail if the user does not
 have sufficient privileges to perform the installation. In this case, the feed and update may not even be downloaded.
 
 Note this has no effect if the update has already been downloaded in the background silently and ready to be resumed.
 
 @param updater The updater instance.
 @param updateCheck The type of update check being performed.
 */
- (BOOL)updater:(SPUUpdater *)updater shouldAllowInstallerInteractionForUpdateCheck:(SPUUpdateCheck)updateCheck;

/**
 Returns the decryption password (if any) which is used to extract the update archive DMG.
 
 Return @c nil if no password should be used.
 
 @param updater The updater instance.
 @return The password used for decrypting the archive, or @c nil if no password should be used.
 */
- (nullable NSString *)decryptionPasswordForUpdater:(SPUUpdater *)updater;

/**
 Called when an update is scheduled to be silently installed on quit after downloading the update automatically.
 
 If the updater is given responsibility, it can later remind the user an update is available if they have not terminated the application for a long time.
 
 Also if the updater is given responsibility and the update item is marked critical, the new update will be presented to the user immediately after.
 
 Even if the @p immediateInstallHandler is not invoked, the installer will attempt to install the update on termination.
 
 @param updater The updater instance.
 @param item The appcast item corresponding to the update that is proposed to be installed.
 @param immediateInstallHandler The install handler to immediately install the update. No UI interaction will be shown and the application will be relaunched after installation.
 @return @c YES if the delegate will handle installing the update or @c NO if the updater should be given responsibility.
 */
- (BOOL)updater:(SPUUpdater *)updater willInstallUpdateOnQuit:(SUAppcastItem *)item immediateInstallationBlock:(void (^)(void))immediateInstallHandler;

/**
 Called after an update is aborted due to an error.
 
 @param updater The updater instance.
 @param error The error that caused the abort
 */
- (void)updater:(SPUUpdater *)updater didAbortWithError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
