# Details on Installer IPC & Security

## Important components:

* The bundle to update & replace
* The application to listen for termination & to relaunch. This can be the same bundle as the one being updated, but this doesn't have to be the case (eg: the bundle being updated could be a plug-in that is hosted by another application).
* The updater that lives in Sparkle.framework - this schedules & downloads updates and starts the installer. This updater's life can be tied to the application's lifetime, but this doesn't have to be the case.
* The installer that is Autoupdate which does all the extraction/installation work. This program is ran as a launchd agent or daemon, depending on whether the updater process submitting it is running as the logged in user or as the root user. Running as the root user is currently experimental.

## After downloading the update:

### Launching the Installer
SUCoreBasedUpdateDriver invokes SUInstallerDriver's extraction method. The updater tries to remove any currently running installer job if there's one running (there normally shouldn't be if we get here, and then launches the Autoupdate installer tool (which is ran from a user caches directory) through a launchd job. This job will run as the logged in user or as the system depending on whether the caller is running as a normal user or as root. The arguments that are passed to Autoupdate are the host bundle identifier and a boolean flag if installation interaction is allowed. The host bundle identifier is necessary for IPC so that we can listen and connect to the same mach service name (which partially uses the bundle identifier). The interaction flag is used if the installer is allowed to request for an authorization prompt and use non-guided package installers.

### Sending Installation Data
After Autoupdate (installer) launches, the updater creates a connection to the installer and sends installation data to the installer using the `SUInstallationData` message. This data includes the bundle application path to relaunch, DSA signature from the appcast item, decryption password for dmg if available, path to GUI updater tool for showing progress, the path to the downloaded directory and name of the downloaded item.

### Update Extraction
If the installer doesn't receive the installation data within a timeout window after the installer set up a listener, then it aborts. Otherwise when the installer receives the data, it starts extracting the update. The installer first sends a `SUExtractionStarted` message. Then it may send several `SUExtractedArchiveWithProgress` messages indicating the unarchival progress back to the updater. On failure, the installer will send `SUArchiveExtractionFailed`. In the updater, if the update is a delta update, then the full archive is downloaded and we go back to the "Sending Installation Data" section to re-send the data and begin extraction again. If the update is not a delta update on the other hand, then the updater aborts causing the installer to abort as well. If the updater didn't receive a `SUExtractionStarted` message within a timeout window after establishing a connection, then it aborts.

### Starting Installation
If the unarchiving succeeds, a `SUValidationStarted` message is sent back to the updater, and the installer begins validating the update. If validation fails, the installer aborts, causing the updater to abort the update as well. Otherwise, the installer sends a message `SUInstallationStartedStage1` to the updater and begins the installation. The installer figures out what kind of installer to use (regular, guided pkg, nonguided pkg) and performs the first stage of installation:

* Regular application installer 1st stage: Makes sure this update is not a downgrade.
* Guided Package installer 1st stage: Does nothing.
* Nonguided Package installer 1st stage: Makes sure /usr/bin/open utility is available.

If the first stage fails, the installer aborts causing the updater to abort the update.

Otherwise a `SUInstallationFinishedStage1` message is sent back to the updater along with some data. This data includes whether the application bundle to relaunch is currently terminated, and whether the installation at later stages can be performed silently (that is, with no user interaction allowed including authorization requests).

The installer then listens and waits for the target application to relaunch terminates. If it is already terminated, then it resumes to stage 2 and 3 of the installation immediately assuming that it does not have permission to show UI interaction to the user. Thus if the installer does not have sufficient privileges to update the application already, the install will fail. If the target is already terminated, the installer will also assume that the target should not be relaunched after installation.

### Installation Waiting Period
The updater receives `SUInstallationFinishedStage1` message. The updater sends a message `SUSentUpdateAppcastItemData` with the appcast data in case the updater may request for it later (due to resumability, discussed later). It also reads if the target has already been terminated (implying that the installer will continue installing the update immediately), and if the installation will be done silently.

For UI based update drivers, the updater tells the user driver to show that the application is ready to be relaunched - the user can continue to install & relaunch the app. The user driver is only alerted however if the installation isn't happening immediately (that is, if the target application to relaunch is still alive). The user driver can decide whether to a) install b) install & relaunch or c) delay installation. If installation is delayed, it can be resumed later, or if the target application terminates, the installer will try to continue installation if it has sufficient privileges to without user interaction.

For automatic based drivers, if the update is not going to be installed immediately and if it can be installed silently, the updater's delegate has a choice to handle the immediate installation of the update. If the delegate handles the installation, it can invoke a block that will trigger the automatic update driver to tell the installer to resume to stage 2 as detailed in step the "Continue to Installation" section - except without displaying any user interface and by relaunching the application afterwards. If the delegate handles the immediate installation, the automatic update driver will not abort, it will just leave the driver running until the installer requests for the app to be terminated later. This means the update can't be resumed later and the user driver won't be involved.

Otherwise if the updater delegate doesn't handle immediate installation for automatic based drivers (assuming still the update is not going to be installed immediately), the update driver is aborted; the installer will still wait for the target to terminate however. If the update cannot be silently installed or if the update is marked as critical from the appcast, the update procedure is actually 'resumed' as a scheduled UI based update driver immediately. The update driver can also be 'resumed' later when the user initiates for an update manually or when a long duration (I think a week) has passed by without the user terminating the application. Note automatic based drivers are unable to do a resume, so only UI based ones can.

If an update driver is resumed (which cannot happen if the target applicaton is already terminated by the way), then the updater first requests the installer for the appcast item data that the installer received before. The updater does this by creating a temporary distinct connection for the purpose of querying for the installation status. The connection will give up if a short timeout passes. If the updater fails to retrieve resume data, it assumes that there's no update to resume and will start back from the beginning. The updater can use this data for showing release notes, etc. Note the updater and target application don't have to live in the same process, and the updater could choose to terminate and resume later as a new process - so having the installer keep the appcast item data is nice.

Afterwards the resumed update driver then allows the user driver to decide whether to a) install the update now, b) install & relaunch the update, or to c) delay the update installation and abort the update driver. Note we are now back to the same options discussed earlier.

### Continue to Installation
If the user driver decides to install the update, it sends a `SUResumeInstallationToStage2` message to the installer and supplies whether the update should be relaunched, and whether user interface can be displayed. The user driver always specifies that the user interface can be displayed; it's only in the case earlier for when the updater's delegate handles immediate installation where UI cannot be displayed.

The installer receives `SUResumeInstallationToStage2` and reads whether it should relaunch the target application and whether it can show UI (thus be allowed to show user interaction). The installer then resumes to stage 2 of the installation if it has not been performed already (that is if the target app already terminated). Note if the installer doesn't receive this message before the target application terminates, then the installer will not relaunch or show UI and resume stage 2 & 3 by itself. Also note that showing UI impacts whether or not the installer can request for authorization.

During this stage, if the installer is allowed to show UI and allowed to show installation interaction, it may request for elevated authorization. If this fails, then the 2nd stage fails, and the installer aborts the update causing the updater to abort as well. If the user explicitly cancels the authorization request, the installer actually treats this as a 'success' so that the updater will be able to abort the update silently. The installer decides to abort after it sends this message in the case the user explicitly cancelled the update however.

If the 2nd stage succeeds, the installer sends a `SUInstallationFinishedStage2` message back to the updater, including if the target application has already terminated at this time, and if the user explicitly cancelled the authorization request.

The updater receives a `SUInstallationFinishedStage2` message, and reads whether the user explicitly cancelled the update and if the target application had already been terminated. If the user cancelled the update, the updater simply aborts. Otherwise if the target application has not already terminated, the updater requests the user driver to terminate the application.

### Pinging the Updater

When the target application is terminated, the installer sends a `SUUpdaterAlivePing` message to the updater. If the updater is still alive by now and receives the message, the updater will then send back a SUUpdaterAlivePong message. This lets the installer know that the updater is still active after the target application is terminated, and whether the installer should later be responsible for displaying updater progress or not if a short time passes by, and the installation is still not finished.

### Finishing the Installation
After the installer sends a ping message to the updater, the installer starts stage 3 of the installation. It is significant to note that a long duration can go by between the 2nd and 3rd stages of installation, so the 2nd stage can't for example place files in temporary directories.

If the GUI progress tool is available and the installer is allowed to show UI and the installer's connection to the updater is disconnected (paritially based on whether a `SUUpdaterAlivePong` was received) and the installer doesn't show progress (only a nonguided pkg installer shows progress), then after a short delay, the progress tool is launched via LaunchServices showing a dock icon and indefinite progress window. Under most circumstances, the installation will finish faster than the progress tool will have the chance to show progress. Potentially large updates with many scattered files and updates over a network may be slow enough to trigger this progress tool. Note that if the connection to the updater is still connected, then it is the updater's job to show progress instead - which can happen when the updater and the target application don't live in the same process (eg: sparkle-cli).

The third stage does the final installation for updating and replacing the new updated bundle.

If the third stage fails, then the installer aborts, causing the updater driver to abort if it's still running. The target application is not ever relaunched on failure.

Otherwise if the third stage succeeds the progress tool is explicitly terminated if it's running (note it will also terminate when the installer terminates due to IPC connection being lost). If the connection to the updater is still alive, a `SUInstallationFinishedStage3` message is sent back to the updater and the updater driver silently aborts the update. The installer then relaunches the new application if the installer was requested to relaunch it, and then does cleanup work (eg, moving old app to trash), and lastly the installer exits.

## Notes:

* Performing an update if the application is already terminated will not request for user authorization, so sufficient privileges are needed beforehand in this case. The common case involves the updater living inside the application so this is not typically a worry.
* We use IPC in such a way that the installer process does not trust the updater process, which is why the installer does extraction, validation, and installation -- all in a single process. The one hole left in our model is the installer shelling out to authorization, which maybe one day can be replaced by knowing when to spawn a system launchd daemon instead. In order to be truely secure, we would need to use SMJobBless() which ensures the helper and app have a matching code signature, but that comes at a big convenience cost, and can be difficult to get working (eg: http://www.openradar.me/20446733), so it may not be worth exploring.
* Some portions of the installer rely on AppKit such as seeing if an application process terminated or launching the update progress tool in the current logged in user session via LaunchServices. Ideally we should remove, replace, or separate out this code into another job in order to be truly daemon safe. Note for most use cases, the installer will be launched as an agent though, unless running sparkle-cli as root for example.
* Removing use cases of `AuthorizationExecuteWithPrivileges()` would require knowing beforehand whether or not the installer may need more privileges. Note in that case this would mean running the entirety of Autoupdate as root. Guided installers will need to require root privileges, but it's questionable if we should allow the appcast (which is untrusted) to specify the type of installation. Also, we currently download updates in the background which can be resumed later because the installer keeps a reference to the download. We would need a way to resume the update by re-launching the installer as root perhaps.
