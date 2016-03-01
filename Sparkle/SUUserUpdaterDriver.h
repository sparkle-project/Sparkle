//
//  SUUserUpdaterDriver.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/14/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SUStatusCompletionResults.h"

@class SUUpdatePermissionPromptResult, SUAppcastItem;
@protocol SUVersionDisplay;

/*!
 The API in Sparkle for controlling the user update interaction.
 
 This protocol is used for implementing a user interface for the Sparkle updater. Sparkle's internal drivers tell
 an object that implements this protocol what actions to take and show to the user.
 
 Every method in this protocol has a void return type and can optionally take a single parameter block, which waits for
 a response back from the user updater driver. Note that every parameter block, or reply, *must* be responded to eventually -
 that is, none can be ignored. Furthermore, they can only be replied to *once* - a reply or completion block should be considered
 invalidated after it's once used. The faster a reply can be made, the more Sparkle may be able to idle, and so the better.
 Lastly, every method in this protocol can be called from any thread. Thus, an implementor may choose to always
 dispatch asynchronously to the main thread. However, an implementor should also avoid unnecessary nested asynchronous dispatches.
 
 An implementor of this protocol should act defensively. For example, it may be possible for an action that says to
 invalidate or dismiss something to be called multiple times in succession, and the implementor may choose to ignore further requests.
 */
@protocol SUUserUpdaterDriver <NSObject>

/*!
 * Show that an update is or is not in progress.
 *
 * A client may choose to update the interface letting the user know the updater is or is not busy.
 * For example, this can be used for menu item validation on the "Check for Updates" action.
 *
 * This can be called from any thread.
 */
- (void)showUpdateInProgress:(BOOL)isUpdateInProgress;

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
- (void)requestUpdatePermissionWithSystemProfile:(NSArray *)systemProfile reply:(void (^)(SUUpdatePermissionPromptResult *))reply;

/*!
 * Show the user initating an update check
 *
 * Respond to the user initiating an update check. Sparkle uses this to show the user a window with an indeterminate progress bar.
 *
 * @param updateCheckStatusCompletion A reply indicating whether the initiated update check is done or cancelled.
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
 * Show the user a new update is found
 *
 * Let the user know a new update is found and ask them what they want to do.
 *
 * @param appcastItem The Appcast Item containing information that reflects the new update
 * @param versionDisplayer The custom version displayer for showing the update's version string
 * @param allowsAutomaticUpdates Indicates whether the user is allowed to use automatic updates.
 * A user interface may use this to give the user an option to enable automatic updates.
 * @param reply A reply of SUInstallUpdateChoice installs the new update immediately. A reply of
 * SUInstallLaterChoice reminds the user later of the update, which can act as a "do nothing" option.
 * Lastly, SUSkipThisVersionChoice skips this particular version and won't bother the user again
 * (unless they initiate an update check themselves).
 *
 * This can be called from any thread
 */
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem versionDisplayer:(id<SUVersionDisplay>)versionDisplayer allowsAutomaticUpdates:(BOOL)allowsAutomaticUpdates reply:(void (^)(SUUpdateAlertChoice))reply;

/*!
 * Show the user a new update that was already automatically downloaded is available
 *
 * Let the user know a new update is found and ask them what they want to do.
 *
 * @param appcastItem The Appcast Item containing information that reflects the new update
 * @param reply A reply of SUInstallUpdateChoice installs the new update immediately. A reply of
 * SUInstallLaterChoice will attempt to install the update when the application terminates; this can act as a
 * "do nothing" option. Lastly, SUSkipThisVersionChoice skips this particular version and won't bother the user again
 * (unless they initiate an update check themselves).
 *
 * This can be called from any thread
 */
- (void)showAutomaticUpdateFoundWithAppcastItem:(SUAppcastItem *)appcastItem reply:(void (^)(SUUpdateAlertChoice))reply;

/*!
 * Show the user a new update was not found
 *
 * Let the user know a new update was not found after they tried initiating an update check.
 *
 * This can be called from any thread
 */
- (void)showUpdateNotFound;

/*!
 * Show the user an update error occurred
 *
 * Let the user know that the updater failed with an error. This will not be invoked without the user having been
 * aware that an update was in progress.
 *
 * This can be called from any thread
 */
- (void)showUpdaterError:(NSError *)error;

/*!
 * Show the user that downloading the new update initiated
 *
 * Let the user know that downloading the new update started.
 *
 * @param downloadUpdateStatusCompletion A reply of SUDownloadUpdateCancelled can be used to cancel
 * the download at any point before -showDownloadFinishedAndStartedExtractingUpdate is invoked.
 * A reply of SUDownloadUpdateDone signifies that the download is done, which should not be invoked until
 * -showDownloadFinishedAndStartedExtractingUpdate
 *
 * This can be called from any thread
 */
- (void)showDownloadInitiatedWithCompletion:(void (^)(SUDownloadUpdateStatus))downloadUpdateStatusCompletion;

/*!
 * Show the user that downloading the new update receieved an initial response
 *
 * This may be an appropriate time to retrieve the expected content length of the download
 * @param response The URL response that contains expected content length of the new update being downloaded
 *
 * This can be called from any thread
 */
- (void)showDownloadDidReceiveResponse:(NSURLResponse *)response;

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
 * This can be called from any thread
 */
- (void)showDownloadFinishedAndStartedExtractingUpdate;

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
 * Show the user that the update finished extracting and is ready to install
 *
 * Let the user know that the update is ready and ask them whether they want to install or not
 *
 * @param installUpdateHandler A reply of SUInstallAndRelaunchUpdateNow installs the update immediately.
 * A reply of SUCancelUpdateInstallation cancels the update installation.
 *
 * This can be called from any thread
 */
- (void)showExtractionFinishedAndReadyToInstallAndRelaunch:(void (^)(SUInstallUpdateStatus))installUpdateHandler;

/*!
 * Show the user that the update is installing
 *
 * Let the user know that the update is currently installing. Sparkle uses this to show an indeterminate progress bar.
 *
 * This can be called from any thread
 */
- (void)showInstallingUpdate;

/*!
 * Register for application termination
 *
 * This is necessary for Sparkle's automatic updates. An implementor should listen for when an application terminates and reply back when it is happening.
 * An implementor may also want to decide if they want to delay the application's termination until -terminateApplication is invoked, which will be
 * necessary if the updater and user updater driver are in separate processes.
 *
 * @param applicationTerminationHandler A reply of SUApplicationWillTerminate should be used when the application is about to terminate. A reply of
 * SUApplicationStoppedObservingTermination can be used to cancel observing application termination. Note this would have the side effect of cancelling
 * the automatic update if it's in progress.
 *
 * This can be called from any thread
 */
- (void)registerApplicationTermination:(void (^)(SUApplicationTerminationStatus))applicationTerminationHandler;

/*!
 * Unregister for application termination
 *
 * Unregister for application termination that was set up in -registerApplicationTermination:
 * This is an appropriate time to reply with SUApplicationStoppedObservingTermination if not having done so already
 *
 * This can be called from any thread
 */
- (void)unregisterApplicationTermination;

/*!
 * Terminate the application
 *
 * Sparkle is signaling that it wants the application to be terminated immediately.
 * If an implementor has already delayed application termination, now would be the appropriate time to stop.
 *
 * This can be called from any thread
 */
- (void)terminateApplication;

/*!
 * Register for system power off
 *
 * This is necessary for Sparkle's automatic updates. An implementor should listen for when the system may shut off and reply back when it is happening.
 *
 * @param systemPowerOffHandler A reply of SUSystemWillPowerOff should be used when the system is about to power off. This has the side effect of Sparkle
 * aborting any updates it has automatically downloaded already. A reply of SUStoppedObservingSystemPowerOff can be used to cancel observing power off.
 * Note this has the same side effect of cancelling an in-progress update.
 *
 * This can be called from any thread
 */
- (void)registerSystemPowerOff:(void (^)(SUSystemPowerOffStatus))systemPowerOffHandler;

/*!
 * Unregister for system power off
 *
 * Unregister for system power off that was set up in -registerSystemPowerOff:
 * This is an appropriate time to reply with SUStoppedObservingSystemPowerOff if not having done so already
 *
 * This can be called from any thread
 */
- (void)unregisterSystemPowerOff;

/*!
 * Dismiss the current update installation
 *
 * Stop and tear down everything. Reply to all outstanding reply/completion blocks.
 * Dismiss all update windows, alerts, progress, etc from the user.
 * Unregister for application termination and system power off if not done so already.
 * Invalidate the update next check if it's running.
 * Basically, stop everything that could have been started. Sparkle may invoke this when aborting or finishing an update.
 *
 * This can be called from any thread
 */
- (void)dismissUpdateInstallation;

@end
