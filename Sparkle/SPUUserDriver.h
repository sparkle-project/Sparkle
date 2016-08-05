//
//  SPUUserDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/14/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUStatusCompletionResults.h"

NS_ASSUME_NONNULL_BEGIN

@class SPUUpdatePermission, SUAppcastItem;

/*!
 The API in Sparkle for controlling the user interaction.
 
 This protocol is used for implementing a user interface for the Sparkle updater. Sparkle's internal drivers tell
 an object that implements this protocol what actions to take and show to the user.
 
 Every method in this protocol has a void return type and can optionally take a single parameter block, which waits for
 a response back from the user driver. Note that every parameter block, or reply, *must* be responded to eventually -
 that is, none can be ignored. Furthermore, they can only be replied to *once* - a reply or completion block should be considered
 invalidated after it's once used. The faster a reply can be made, the more Sparkle may be able to idle, and so the better.
 Lastly, every method in this protocol can be called from any thread. Thus, an implementor may choose to always
 dispatch asynchronously to the main thread. However, an implementor should also avoid unnecessary nested asynchronous dispatches.
 
 An implementor of this protocol should act defensively. For example, it may be possible for an action that says to
 invalidate or dismiss something to be called multiple times in succession, and the implementor may choose to ignore further requests.
 */
@protocol SPUUserDriver <NSObject>

/*!
 * Show that an update can be checked by the user or not
 *
 * A client may choose to update the interface letting the user know if they can check for updates.
 * For example, this can be used for menu item validation on the "Check for Updates" action.
 *
 * This can be called from any thread.
 */
- (void)showCanCheckForUpdates:(BOOL)canCheckForUpdates;

/*!
 * Idle on timed updater checks.
 *
 * If the user driver should idle on update checks, then it shouldn't have to schedule any update checks.
 * If we can idle on update checks, this means the updater just determined that automatic update checks were disabled
 *
 * @param shouldIdleOnUpdateChecks Indicates if the user driver should idle on updater checks
 *
 * This can be called from any thread.
 */
- (void)idleOnUpdateChecks:(BOOL)shouldIdleOnUpdateChecks;

/*!
 * Start the next scheduled update check timer.
 *
 * @param timeInterval The time interval or delay since now that should be used to initiate the next update check.
 * @param reply A reply of SUCheckForUpdateNow will tell Sparkle to start its update check immediately. This should not be called sooner
 * than the timeInterval delay. A reply of SUCheckForUpdateWillOccurLater can be used immediately however, allowing Sparkle to idle.
 * If a SUCheckForUpdateWillOccurLater reply is used, then someone after the delay must be delegated to telling the SUUpdater to check for the next update.
 *
 * This can be called from any thread.
 */
- (void)startUpdateCheckTimerWithNextTimeInterval:(NSTimeInterval)timeInterval reply:(void (^)(SUUpdateCheckTimerStatus))reply;

/*!
 * Invalidate the update check timer.
 *
 * Stop the update check initated from -startUpdateCheckTimerWithNextTimeInterval:reply:
 * Only if a response hasn't been sent yet, then send a SUCheckForUpdateWillOccurLater reply
 *
 * This can be called from any thread, and could be called multiple times in succession.
 */
- (void)invalidateUpdateCheckTimer;

/*!
 * Request updater permission from the user
 *
 * Ask the user if they want automatic update checks to be on or off, and if they want to send an anonymous system profile
 * This is typically only called once per app installation.
 *
 * @param reply A reply supplying whether the user wants automatic update checks off or on, and whether they want to send their system profile
 *
 * This can be called from any thread
 */
- (void)requestUpdatePermissionWithSystemProfile:(NSArray *)systemProfile reply:(void (^)(SPUUpdatePermission *))reply;

/*!
 * Show the user initating an update check
 *
 * Respond to the user initiating an update check. Sparkle uses this to show the user a window with an indeterminate progress bar.
 *
 * @param updateCheckStatusCompletion A reply indicating whether the initiated update check is done or canceled.
 * Attempts to canceling can be made before -dismissUserInitiatedUpdateCheck is invoked. Replying with SUUserInitiatedCheckDone
 * on the other hand should not be done until -dismissUserInitiatedUpdateCheck is invoked.
 *
 * This can be called from any thread
 */
- (void)showUserInitiatedUpdateCheckWithCompletion:(void (^)(SUUserInitiatedCheckStatus))updateCheckStatusCompletion;

/*!
 * Dismiss the user initiated update check from the user
 *
 * Dismiss whatever was started in -showUserInitiatedUpdateCheckWithCompletion:
 * This is an appropriate time to reply with SUUserInitiatedCheckDone if not having done so already
 *
 * This can be called from any thread
 */
- (void)dismissUserInitiatedUpdateCheck;

/*!
 * Show the user a new update is found and can be downloaded & installed
 *
 * Let the user know a new downloadable update is found and ask them what they want to do.
 *
 * @param appcastItem The Appcast Item containing information that reflects the new update
 *
 * @param reply
 * A reply of SUInstallUpdateChoice begins downloading and installing the new update.
 *
 * A reply of SUInstallLaterChoice reminds the user later of the update, which can act as a "do nothing" option.
 *
 * A reply of SUSkipThisVersionChoice skips this particular version and won't bother the user again,
 * unless they initiate an update check themselves.
 *
 * This can be called from any thread
 */
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem reply:(void (^)(SUUpdateAlertChoice))reply;

/*!
 * Show the user a new update has been downloaded and can be installed
 *
 * This method behaves just like -showUpdateFoundWithAppcastItem:reply: except the update has already been downloaded.
 */
- (void)showDownloadedUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem reply:(void (^)(SUUpdateAlertChoice))reply;

/*!
 * Show the user an update that has started installing can be resumed and installed immediately
 *
 * Let the user know an update that has already been downloaded and started installing can be resumed.
 * Note at this point the update cannot be canceled.
 *
 * @param appcastItem The Appcast Item containing information that reflects the new update
 *
 * @param reply A reply of SUInstallAndRelaunchUpdateNow installs the update immediately and relaunches the new update.
 * A reply of SUInstallUpdateNow installs the update immediately but does not relaunch the new update.
 * A reply of SUDismissUpdateInstallation dismisses the update installation. Note the update will attempt to finish installation
 * after the application terminates.
 *
 * This can be called from any thread
 */
- (void)showResumableUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem reply:(void (^)(SUInstallUpdateStatus))reply;

/*!
 * Show the user the release notes for the new update
 *
 * Display the release notes to the user. This will be called after showing the new update.
 * This is only applicable if the release notes are linked from the appcast, and are not directly embedded inside of the appcast file.
 * That is, this may be invoked if the releaseNotesURL from the appcast item is non-nil.
 *
 * @param releaseNotes The data for the release notes that was downloaded from the new update's appcast.
 *
 * This can be called from any thread
 */
- (void)showUpdateReleaseNotes:(NSData *)releaseNotes;

/*!
 * Show the user that the new update's release notes could not be downloaded
 *
 * This will be called after showing the new update.
 * This is only applicable if the release notes are linked from the appcast, and are not directly embedded inside of the appcast file.
 * That is, this may be invoked if the releaseNotesURL from the appcast item is non-nil.
 *
 * @param error The error associated with why the new update's release notes could not be downloaded.
 *
 * This can be called from any thread
 */
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error;

/*!
 * Show the user a new update was not found
 *
 * Let the user know a new update was not found after they tried initiating an update check.
 *
 * @param acknowledgement Acknowledge to the updater that no update found was shown.
 *
 * This can be called from any thread
 */
- (void)showUpdateNotFoundWithAcknowledgement:(void (^)(void))acknowledgement;

/*!
 * Show the user an update error occurred
 *
 * Let the user know that the updater failed with an error. This will not be invoked without the user having been
 * aware that an update was in progress.
 *
 * @param acknowledgement Acknowledge to the updater that the error was shown.
 *
 * This can be called from any thread
 */
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))acknowledgement;

/*!
 * Show the user that downloading the new update initiated
 *
 * Let the user know that downloading the new update started.
 *
 * @param downloadUpdateStatusCompletion A reply of SUDownloadUpdateCanceled can be used to cancel
 * the download at any point before -showDownloadDidStartExtractingUpdate is invoked.
 * A reply of SUDownloadUpdateDone signifies that the download is done, which should not be invoked until
 * -showDownloadDidStartExtractingUpdate
 *
 * This can be called from any thread
 */
- (void)showDownloadInitiatedWithCompletion:(void (^)(SUDownloadUpdateStatus))downloadUpdateStatusCompletion;

/*!
 * Show the user the content length of the new update that will be downloaded
 *
 * @param expectedContentLength The expected content length of the new update being downloaded. This will be greater than 0.
 *
 * This can be called from any thread
 */
- (void)showDownloadDidReceiveExpectedContentLength:(NSUInteger)expectedContentLength;

/*!
 * Show the user that the update download received more data
 *
 * This may be an appropriate time to advance a visible progress indicator of the download
 * @param length The length of the data that was just downloaded
 *
 * This can be called from any thread
 */
- (void)showDownloadDidReceiveDataOfLength:(NSUInteger)length;

/*!
 * Show the user that the update finished downloading and started extracting
 *
 * This is an appropriate time to reply with SUDownloadUpdateDone if not done so already
 * Sparkle uses this to show an indeterminate progress bar.
 *
 * Note that an update can resume at this point after having been downloaded before,
 * so this may be called without any of the download callbacks being invoked prior.
 *
 * This can be called from any thread
 */
- (void)showDownloadDidStartExtractingUpdate;

/*!
 * Show the user that the update is extracting with progress
 *
 * Let the user know how far along the update extraction is.
 *
 * @param progress The progress of the extraction from a 0.0 to 1.0 scale
 *
 * This can be called from any thread
 */
- (void)showExtractionReceivedProgress:(double)progress;

/*!
 * Show the user that the update is ready to install
 *
 * Let the user know that the update is ready and ask them whether they want to install or not.
 * Note if the target application is already terminated and an update can be performed silently, this method may not be invoked.
 *
 * @param installUpdateHandler A reply of SUInstallAndRelaunchUpdateNow installs the update immediately and relaunches the new update.
 * A reply of SUInstallUpdateNow installes the update immediately but does not relaunch the new update.
 * A reply of SUDismissUpdateInstallation dismisses the update installation. Note the update may still be installed after
 * the application terminates, however there is not a strong guarantee that this will happen.
 *
 * This can be called from any thread
 */
- (void)showReadyToInstallAndRelaunch:(void (^)(SUInstallUpdateStatus))installUpdateHandler;

/*!
 * Show the user that the update is installing
 *
 * Let the user know that the update is currently installing. Sparkle uses this to show an indeterminate progress bar.
 *
 * This can be called from any thread
 */
- (void)showInstallingUpdate;

/*!
 * Terminate the application
 *
 * Sparkle is signaling that it wants the application to request for application termination.
 * Care should be taken if the request for application termination fails or is delayed.
 * Eg: may want to hide installation status windows in case termination doesn't happen right away
 *
 * This can be called from any thread
 */
- (void)terminateApplication;

/*!
 * Show the user that the update installation finished
 *
 * Let the user know that the update finished installing.
 * This will only be invoked if the updater process is still alive, which is typically not the case if
 * the updater's lifetime is tied to the application it is updating.
 *
 * This can be called from any thread
 */
- (void)showUpdateInstallationDidFinish;

/*!
 * Dismiss the current update installation
 *
 * Stop and tear down everything. Reply to all outstanding reply/completion blocks.
 * Dismiss all update windows, alerts, progress, etc from the user.
 * Unregister for application termination and system power off if not done so already.
 * Basically, stop everything that could have been started. Sparkle may invoke this when aborting or finishing an update.
 * Do not, however, invaldate the next update check timer.
 *
 * This can be called from any thread, and could be called multiple times in succession.
 */
- (void)dismissUpdateInstallation;

@end

NS_ASSUME_NONNULL_END
