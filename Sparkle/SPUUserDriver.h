//
//  SPUUserDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/14/16.
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

#import "SPUStatusCompletionResults.h"
#import "SUExport.h"

NS_ASSUME_NONNULL_BEGIN

@class SPUUpdatePermissionRequest, SUUpdatePermissionResponse, SUAppcastItem, SPUDownloadData;

/*!
 The API in Sparkle for controlling the user interaction.
 
 This protocol is used for implementing a user interface for the Sparkle updater. Sparkle's internal drivers tell
 an object that implements this protocol what actions to take and show to the user.
 
 Every method in this protocol can be assumed to be called from the main thread.
 */
SU_EXPORT @protocol SPUUserDriver <NSObject>

/*!
 * Show that an update can be checked by the user or not
 *
 * A client may choose to update the interface letting the user know if they can check for updates.
 */
- (void)showCanCheckForUpdates:(BOOL)canCheckForUpdates;

/*!
 * Show an updater permission request to the user
 *
 * Ask the user for their permission regarding update checks.
 * This is typically only called once per app installation.
 *
 * @param request The update permission request.
 * @param reply A reply with a update permission response.
 */
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply;

/*!
 * Show the user initating an update check
 *
 * Respond to the user initiating an update check. Sparkle uses this to show the user a window with an indeterminate progress bar.
 *
 * @param cancellation Invoke this cancellation block to cancel the update check.
 * Attempts to canceling can be made before -dismissUserInitiatedUpdateCheck is invoked.
 */
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancellation;

/*!
 * Dismiss the user initiated update check from the user
 *
 * Dismiss whatever was started in -showUserInitiatedUpdateCheckWithCompletion:
 */
- (void)dismissUserInitiatedUpdateCheck;

/*!
 * Show the user a new update is found and can be downloaded and installed
 *
 * Let the user know a new update is found and ask them what they want to do.
 *
 * @param appcastItem The Appcast Item containing information that reflects the new update
 *
 * @param userInitiated A flag indicating whether or not a user initiated this update check
 *
 * @param reply
 * A reply of SPUInstallUpdateChoice begins downloading and installing the new update.
 *
 * A reply of SPUInstallLaterChoice reminds the user later of the update, which can act as a "do nothing" option.
 *
 * A reply of SPUSkipThisVersionChoice skips this particular version and won't bother the user again,
 * unless they initiate an update check themselves.
 */
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem userInitiated:(BOOL)userInitiated reply:(void (^)(SPUUpdateAlertChoice))reply;

/*!
 * Show the user a new update has been downloaded and can be installed
 *
 * This method behaves just like -showUpdateFoundWithAppcastItem:reply: except the update has already been downloaded.
 */
- (void)showDownloadedUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem userInitiated:(BOOL)userInitiated reply:(void (^)(SPUUpdateAlertChoice))reply;

/*!
 * Show the user an update that has started installing can be resumed and installed immediately
 *
 * Let the user know an update that has already been downloaded and started installing can be resumed.
 * Note at this point the update cannot be canceled.
 *
 * @param appcastItem The Appcast Item containing information that reflects the new update
 *
 * @param userInitiated A flag indicating whether or not a user initiated this update check
 *
 * @param reply
 * A reply of SPUInstallAndRelaunchUpdateNow installs the update immediately and relaunches the new update.
 * Note: the application is not relaunched if it was not running before installing the update.
 * A reply of SPUInstallUpdateNow installs the update immediately but does not relaunch the new update.
 * A reply of SPUDismissUpdateInstallation dismisses the update installation. Note the update will attempt to finish installation
 * after the application terminates.
 */
- (void)showResumableUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem userInitiated:(BOOL)userInitiated reply:(void (^)(SPUInstallUpdateStatus))reply;

/*!
 * Show the user a new informational only update has been found
 *
 * Let the user know a new informational update is found and ask them what they want to do.
 *
 * @param appcastItem The Appcast Item containing information that reflects the new update.
 * The infoURL property for the appcastItem may be of interest.
 *
 * @param userInitiated A flag indicating whether or not a user initiated this update check
 *
 * @param reply
 * A reply of SPUDismissInformationalNoticeChoice dismisses this notice.
 * An implementor may decide to invoke another action before dismissing the notice.
 *
 * A reply of SPUSkipThisInformationalVersionChoice skips this particular version and won't bother the user again,
 * unless they initiate an update check themselves.
 */
- (void)showInformationalUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem userInitiated:(BOOL)userInitiated reply:(void (^)(SPUInformationalUpdateAlertChoice))reply;

/*!
 * Show the user the release notes for the new update
 *
 * Display the release notes to the user. This will be called after showing the new update.
 * This is only applicable if the release notes are linked from the appcast, and are not directly embedded inside of the appcast file.
 * That is, this may be invoked if the releaseNotesURL from the appcast item is non-nil.
 *
 * @param downloadData The data for the release notes that was downloaded from the new update's appcast.
 */
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)downloadData;

/*!
 * Show the user that the new update's release notes could not be downloaded
 *
 * This will be called after showing the new update.
 * This is only applicable if the release notes are linked from the appcast, and are not directly embedded inside of the appcast file.
 * That is, this may be invoked if the releaseNotesURL from the appcast item is non-nil.
 *
 * @param error The error associated with why the new update's release notes could not be downloaded.
 */
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error;

/*!
 * Show the user a new update was not found
 *
 * Let the user know a new update was not found after they tried initiating an update check.
 *
 * @param error The error associated with why a new update was not found.
 * @param acknowledgement Acknowledge to the updater that no update found error was shown.
 */
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement;

/*!
 * Show the user an update error occurred
 *
 * Let the user know that the updater failed with an error. This will not be invoked without the user having been
 * aware that an update was in progress.
 *
 * @param error The error associated with what update error occurred..
 * @param acknowledgement Acknowledge to the updater that the error was shown.
 */
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement;

/*!
 * Show the user that downloading the new update initiated
 *
 * Let the user know that downloading the new update started.
 *
 * @param cancellation Invoke this cancellation block to cancel the download at any point before -showDownloadDidStartExtractingUpdate is invoked.
 */
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancellation;

/*!
 * Show the user the content length of the new update that will be downloaded
 *
 * @param expectedContentLength The expected content length of the new update being downloaded.
 * An implementor should be able to handle if this value is invalid (more or less than actual content length downloaded).
 * Additionally, this method may be called more than once for the same download in rare scenarios.
 */
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)expectedContentLength;

/*!
 * Show the user that the update download received more data
 *
 * This may be an appropriate time to advance a visible progress indicator of the download
 * @param length The length of the data that was just downloaded
 */
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length;

/*!
 * Show the user that the update finished downloading and started extracting
 *
 * Sparkle uses this to show an indeterminate progress bar.
 *
 * Note that an update can resume at this point after having been downloaded before,
 * so this may be called without any of the download callbacks being invoked prior.
 */
- (void)showDownloadDidStartExtractingUpdate;

/*!
 * Show the user that the update is extracting with progress
 *
 * Let the user know how far along the update extraction is.
 *
 * @param progress The progress of the extraction from a 0.0 to 1.0 scale
 */
- (void)showExtractionReceivedProgress:(double)progress;

/*!
 * Show the user that the update is ready to install
 *
 * Let the user know that the update is ready and ask them whether they want to install or not.
 * Note if the target application is already terminated and an update can be performed silently, this method may not be invoked.
 *
 * @param installUpdateHandler
 * A reply of SPUInstallAndRelaunchUpdateNow installs the update immediately and relaunches the new update.
 * Note: the application is not relaunched if it was not running before installing the update.
 * A reply of SPUInstallUpdateNow installes the update immediately but does not relaunch the new update.
 * A reply of SPUDismissUpdateInstallation dismisses the update installation. Note the update may still be installed after
 * the application terminates, however there is not a strong guarantee that this will happen.
 */
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUInstallUpdateStatus))installUpdateHandler;

/*!
 * Show the user that the update is installing
 *
 * Let the user know that the update is currently installing. Sparkle uses this to show an indeterminate progress bar.
 */
- (void)showInstallingUpdate;

/*!
 * Show or dismiss progress while a termination signal is being sent to the application
 *
 * Terminating and relaunching the application (if requested to be relaunched) may happen quickly,
 * or it may take some time to perform the final installation, or the termination signal can be canceled or delayed by the application or user.
 *
 * It is up to the implementor whether or not to decide to continue showing installation progress
 * or dismissing UI that won't remain obscuring other parts of the user interface.
 */
- (void)showSendingTerminationSignal;

/*!
 * Show the user that the update installation finished
 *
 * Let the user know that the update finished installing.
 * This will only be invoked if the updater process is still alive, which is typically not the case if
 * the updater's lifetime is tied to the application it is updating.
 *
 * @param acknowledgement Acknowledge to the updater that the installation finish was shown.
 */
- (void)showUpdateInstallationDidFinishWithAcknowledgement:(void (^)(void))acknowledgement;

/*!
 * Dismiss the current update installation
 *
 * Stop and tear down everything.
 * Dismiss all update windows, alerts, progress, etc from the user.
 * Basically, stop everything that could have been started. Sparkle may invoke this when aborting or finishing an update.
 */
- (void)dismissUpdateInstallation;

/*
 * Below are deprecated methods that have been replaced by better alternatives.
 * The deprecated methods will be used if the alternatives have not been implemented yet.
 * In the future support for using these deprecated methods may be removed however.
 */
@optional

- (void)showUpdateNotFoundWithAcknowledgement:(void (^)(void))acknowledgement __deprecated_msg("Implement -showUpdateNotFoundWithError:acknowledgement: instead");

- (void)showUserInitiatedUpdateCheckWithCompletion:(void (^)(SPUUserInitiatedCheckStatus))updateCheckStatusCompletion __deprecated_msg("Implement -showUserInitiatedUpdateCheckWithCancellation: instead");

- (void)showDownloadInitiatedWithCompletion:(void (^)(SPUDownloadUpdateStatus))downloadUpdateStatusCompletion __deprecated_msg("Implement -showDownloadInitiatedWithCancellation: instead");

@end

NS_ASSUME_NONNULL_END
