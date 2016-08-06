//
//  SUUpdaterDelegate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/12/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUExport.h"

@protocol SUVersionComparison;
@class SUAppcast, SUAppcastItem;

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
//	SUUpdater Delegate:
// -----------------------------------------------------------------------------

/*!
 Provides methods to control the behavior of an SUUpdater object.
 */
@protocol SUUpdaterDelegate <NSObject>
@optional

/*!
 Returns whether to allow Sparkle to pop up.
 
 For example, this may be used to prevent Sparkle from interrupting a setup assistant.
 
 \param updater The updater instance.
 */
- (BOOL)updaterMayCheckForUpdates:(id)updater;

/*!
 Returns additional parameters to append to the appcast URL's query string.
 
 This is potentially based on whether or not Sparkle will also be sending along the system profile.
 
 \param updater The updater instance.
 \param sendingProfile Whether the system profile will also be sent.
 
 \return An array of dictionaries with keys: "key", "value", "displayKey", "displayValue", the latter two being specifically for display to the user.
 */
- (NSArray *)feedParametersForUpdater:(id)updater sendingSystemProfile:(BOOL)sendingProfile;

/*!
 Returns a custom appcast URL.
 
 Override this to dynamically specify the entire URL.
 
 \param updater The updater instance.
 */
- (NSString *)feedURLStringForUpdater:(id)updater;

/*!
 Returns whether Sparkle should prompt the user about automatic update checks.
 
 Use this to override the default behavior.
 
 \param updater The updater instance.
 */
- (BOOL)updaterShouldPromptForPermissionToCheckForUpdates:(id)updater;

/*!
 Called after Sparkle has downloaded the appcast from the remote server.
 
 Implement this if you want to do some special handling with the appcast once it finishes loading.
 
 \param updater The updater instance.
 \param appcast The appcast that was downloaded from the remote server.
 */
- (void)updater:(id)updater didFinishLoadingAppcast:(SUAppcast *)appcast;

/*!
 Returns the item in the appcast corresponding to the update that should be installed.
 
 If you're using special logic or extensions in your appcast,
 implement this to use your own logic for finding a valid update, if any,
 in the given appcast.
 
 \param appcast The appcast that was downloaded from the remote server.
 \param updater The updater instance.
 */
- (SUAppcastItem *)bestValidUpdateInAppcast:(SUAppcast *)appcast forUpdater:(id)updater;

/*!
 Called when a valid update is found by the update driver.
 
 \param updater The updater instance.
 \param item The appcast item corresponding to the update that is proposed to be installed.
 */
- (void)updater:(id)updater didFindValidUpdate:(SUAppcastItem *)item;

/*!
 Called when a valid update is not found.
 
 \param updater The updater instance.
 */
- (void)updaterDidNotFindUpdate:(id)updater;

/*!
 Returns whether the release notes (if available) should be downloaded after an update is found and shown.
 
 This is specifically for the releaseNotesLink element in the appcast.
 
 \param updater The updater instance.
 
 \return \c YES to download and show the release notes if available
 */
- (BOOL)updaterShouldDownloadReleaseNotes:(id)updater;

/*!
 Called immediately before downloading the specified update.
 
 \param updater The updater instance.
 \param item The appcast item corresponding to the update that is proposed to be downloaded.
 \param request The mutable URL request that will be used to download the update.
 */
- (void)updater:(id)updater willDownloadUpdate:(SUAppcastItem *)item withRequest:(NSMutableURLRequest *)request;

/*!
 Called after the specified update failed to download.
 
 \param updater The updater instance.
 \param item The appcast item corresponding to the update that failed to download.
 \param error The error generated by the failed download.
 */
- (void)updater:(id)updater failedToDownloadUpdate:(SUAppcastItem *)item error:(NSError *)error;

/*!
 Called when the user clicks the cancel button while and update is being downloaded.
 
 \param updater The updater instance.
 */
- (void)userDidCancelDownload:(id)updater;

/*!
 Called immediately before installing the specified update.
 
 \param updater The updater instance.
 \param item The appcast item corresponding to the update that is proposed to be installed.
 */
- (void)updater:(id)updater willInstallUpdate:(SUAppcastItem *)item;

/*!
 \deprecated Use -updater:shouldPostponeRelaunchForUpdate:untilInvokingBlock: instead
 Returns whether the relaunch should be delayed in order to perform other tasks.
 
 This is not called if the user didn't relaunch on the previous update,
 in that case it will immediately restart.
 
 This may also not be called if the application is not going to relaunch after it terminates.
 
 \param updater The updater instance.
 \param item The appcast item corresponding to the update that is proposed to be installed.
 \param invocation The invocation that must be completed before continuing with the relaunch.
 
 \return \c YES to delay the relaunch until \p invocation is invoked.
 */
- (BOOL)updater:(id)updater shouldPostponeRelaunchForUpdate:(SUAppcastItem *)item untilInvoking:(NSInvocation *)invocation __deprecated;

/*!
 Returns whether the relaunch should be delayed in order to perform other tasks.
 
 This is not called if the user didn't relaunch on the previous update,
 in that case it will immediately restart.
 
 This may also not be called if the application is not going to relaunch after it terminates.
 
 \param updater The updater instance.
 \param item The appcast item corresponding to the update that is proposed to be installed.
 \param installHandler The install handler that must be completed before continuing with the relaunch.
 
 \return \c YES to delay the relaunch until \p installHandler is invoked.
 */
- (BOOL)updater:(id)updater shouldPostponeRelaunchForUpdate:(SUAppcastItem *)item untilInvokingBlock:(void (^)(void))installHandler;

/*!
 Returns whether the application should be relaunched at all.
 
 Some apps \b cannot be relaunched under certain circumstances.
 This method can be used to explicitly prevent a relaunch.
 
 \param updater The updater instance.
 */
- (BOOL)updaterShouldRelaunchApplication:(id)updater;

/*!
 Called immediately before relaunching.
 
 \param updater The updater instance.
 */
- (void)updaterWillRelaunchApplication:(id)updater;

/*!
 Returns an object that compares version numbers to determine their arithmetic relation to each other.
 
 This method allows you to provide a custom version comparator.
 If you don't implement this method or return \c nil,
 the standard version comparator will be used. Note that the
 standard version comparator may be used during installation for preventing
 a downgrade, even if you provide a custom comparator here.
 
 \sa SUStandardVersionComparator
 
 \param updater The updater instance.
 */
- (id<SUVersionComparison>)versionComparatorForUpdater:(id)updater;

/*!
 \deprecated See SUStandardUserUpdaterDriver delegate instead.
 
 Returns an object that formats version numbers for display to the user.
 If you don't implement this method or return \c nil, the standard version formatter will be used.
 
 \sa SUUpdateAlert
 \param updater The updater instance.
 */
- (id)versionDisplayerForUpdater:(id)updater __deprecated; // Don't specify SUVersionDisplay in the return type, otherwise we'd have to forward declare a protocol that isn't used here anymore

/*!
 Returns the path to the application which is used to relaunch after the update is installed.
 
 The installer also waits for the termination of the application at this path.
 
 The default is the path of the host bundle.
 
 \param updater The updater instance.
 */
- (NSString *)pathToRelaunchForUpdater:(id)updater;

/*!
 Returns whether or not the updater should allow interaction with its installer
 
 Use this to override the default behavior which is to allow interaction with the installer.
 
 If interaction is allowed, then an authorization prompt may show up to the user if they do
 not curently have sufficient privileges to perform the installation of the new update.
 
 On the other hand, if interaction is not allowed, then an installation may fail if the user does not
 have sufficient privileges to perform the installation.
 
 \param updater The updater instance.
 */
- (BOOL)updaterShouldAllowInstallerInteraction:(id)updater;

/*!
 Returns the decryption password (if any) which is used to extract the update archive DMG.
 
 Return nil if no password should be used.
 
 \param updater The updater instance.
 */
- (NSString *)decryptionPasswordForUpdater:(id)updater;

/*!
 Called before an updater shows a modal alert window,
 to give the host the opportunity to hide attached windows that may get in the way.
 
 \param updater The updater instance.
 
 @deprecated See SUStandardUserUpdaterDriver delegate instead.
 */
- (void)updaterWillShowModalAlert:(id)updater __deprecated;

/*!
 Called after an updater shows a modal alert window,
 to give the host the opportunity to hide attached windows that may get in the way.
 
 \param updater The updater instance.
 
 @deprecated See SUStandardUserUpdaterDriver delegate instead.
 */
- (void)updaterDidShowModalAlert:(id)updater __deprecated;

/*!
 Called when an update is scheduled to be silently installed on quit.
 
 \param updater The updater instance.
 \param item The appcast item corresponding to the update that is proposed to be installed.
 \param invocation Can be used to trigger an immediate silent install and relaunch.
 
 \deprecated See -updater:willInstallUpdateOnQuit:immediateInstallationBlock: instead. If this method is implemented, Sparkle will assume the delegate is given responsibility to handling the update without a choice. For this reason, please don't implement this method.
 */
- (void)updater:(id)updater willInstallUpdateOnQuit:(SUAppcastItem *)item immediateInstallationInvocation:(NSInvocation *)invocation __deprecated;

/*!
 Called when an update is scheduled to be silently installed on quit after downloading the update automatically.
 
 \param updater The updater instance.
 \param item The appcast item corresponding to the update that is proposed to be installed.
 \param immediateInstallHandler The install handler to immediately install the update. No UI interaction will be shown and the application will be relaunched after installation.
 \return Return YES if the delegate will handle installing the update or NO if the updater should be given responsibility.
 
 If the updater is given responsibility, it can later remind the user an update is available if they have not terminated the application for a long time.
 Also if the updater is given responsibility and the update item is marked critical, the new update will be presented to the user immediately after.
 Even if the immediateInstallHandler is not invoked, the installer will attempt to install the update on termination.
 */
- (BOOL)updater:(id)updater willInstallUpdateOnQuit:(SUAppcastItem *)item immediateInstallationBlock:(void (^)(void))immediateInstallHandler;

/*!
 Calls after an update that was scheduled to be silently installed on quit has been canceled.
 
 \param updater The updater instance.
 \param item The appcast item corresponding to the update that was proposed to be installed.
 
  \deprecated This method is no longer invoked. The installer will try to its best ability to install the update.
 */
- (void)updater:(id)updater didCancelInstallUpdateOnQuit:(SUAppcastItem *)item __deprecated;

/*!
 Called after an update is aborted due to an error.
 
 \param updater The updater instance.
 \param error The error that caused the abort
 */
- (void)updater:(id)updater didAbortWithError:(NSError *)error;

@end
