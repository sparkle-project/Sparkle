# Details on Installer IPC & Security

## Important components:

* The bundle to update & replace
* The application to listen for termination & to relaunch. This can be the same bundle as the one being updated, but this doesn't have to be the case (eg: the bundle being updated could be a plug-in that is hosted by another application).
* The updater that lives in Sparkle.framework - this schedules & downloads updates and starts the installer. This updater's life can be tied to the application's lifetime, but this doesn't have to be the case.
* The installer (Autoupdate) which does all the extraction, validation, and installation work. This program is submitted by the updater and is run as a launchd agent or daemon, depending on the type of installation and if elevated permissions are needed to perform the update.
* The progress or agent application which hosts the installation status service and is also responsible for showing UI if the installation takes a sufficiently long period of time, as well as responsible for launching the new update.

## After downloading the update:

### Launching the Installer
SPUCoreBasedUpdateDriver invokes SPUInstallerDriver's extraction method which invokes SUInstallerLauncher's launch installer method. An XPC Service may be used to launch the installer if necessary for Sandboxed applications.

First, if the updater driver that invoked the launcher doesn't allow for interaction (in particular, the automatic/silent update driver does not allow interaction), then the launcher fails with a hint to try again with interaction enabled (in particular, with a UI based update driver). If this happens, the updater keeps a reference to the downloaded update and appcast item that is used for resuming with a UI based update driver later. The launcher in this case is telling that authorization can only be done if interaction is allowed from the driver, so the user can enter their password to start up the installer as root to install over a location that requires such privileges.

The launcher then looks for the installer and agent application. If we are inside the XPC Service, a relative path back to the framework auxiliary directory is computed otherwise the bundle's auxiliary directory path is retrieved. Once those paths are found, the launcher copies the progress agent application to a temporary cache location. The installer is not copied because it is a plain single executable that does not rely on external relative dependencies, whereas the agent application relies on bundle resources. This is important to consider because the old application may be moved around and removed when the installation process occurs. Leaving the installer inside its bundle also could leave it in a place the user doesn't necessarily have write privileges to.

The installer is first submitted. If it requires root privileges, it will ask for an admin user name and password. How it determines if root privileges are necessary is based on:

* If the installation type from the appcast is an interactive package based installer, then no root privileges are necessary because the package installer will ask for them. Note this type of installation is deprecated however.
* If the installation type from the appcast is a guided or regular package based installer, then root privileges are necessary because the system installer utility has to run as root.
* Otherwise the installation type is a normal application update, and root privileges are only needed if write permission or changing the owner is currently insufficient.

The installer makes sure, after extraction, that the expected installation type from the appcast matches the type of installation found within the archive. So this hint from the appcast is not just trusted implicitly.

If the user cancels submitting the installer on authorization (if it's required), the launcher aborts the installation process silently. If everything goes alright, the progress agent application is submitted next. If either of the submissions fail, the installation fails and aborts, otherwise the launcher succeeds and its job is done. Note before the submissions are done, the jobs are removed from launchd, and the jobs are submitted in a way that act as "one-time" jobs. If they fail or succeed, the jobs aren't restarted, and the jobs aren't installed in a system location for launchd to attempt launching again.

The most important argument passed to the installer is the host bundle identifier of the bundle to update. This bundle identifier is used so that the installer and updater know what Mach service to connect to for IPC. Mostly everything else to the installer is sent via a XPC connection. The host bundle path is passed to the progress agent, which is just used for obtaining the bundle identifier, and for UI purposes (eg: displaying app icon and name when the app needs to show progress). The type of domain the installer is running in (user vs system) is also passed to the progress agent application so it can know which domain to use to connect to the installer.

### Timeouts

Upon starting the progress agent, it tries to establish a connection to the installer and send a "hello" message expecting a reply back. If a reply isn't received back within a certain threshold, the agent application aborts (unless it's already planning to terminate in the near future after relaunching the new update).

If the installer doesn't receive the "hello" message from the agent in a certain threshold, the installer aborts. If the installer doesn't receive the installation input data from the data in a certain threshold also, it aborts there too. If the installer aborts and the agent is connected to the installer, the agent will abort as well.

When the updater attempts to set up a connection to the installer, after a certain threshold, if the installation hasn't progressed from not beginning (i.e, extraction hasn't begun), then the updater aborts the installation.

### Installation Data
After the installer launches, the updater creates a connection to the installer and sends installation data to the installer using the `SPUInstallationData` message. This data includes the bundle application path to relaunch, the path to the bundle to update and replace, Ed(DSA) signature from the appcast item, decryption password for dmg if available, the path to the downloaded directory and name of the downloaded item, and the type of expected installation.

The installer takes note of all this information, but it moves the downloaded item into a update directory it chooses for itself. This is for two reasons:

1. If the installer is running at a higher level than the process that submitted it (eg: sandboxed -> user, or user -> root), it make sense from a security perspective to move the file into its own support directory. This could prevent an attacker from manipulating the download while the installer is using it.
2. The updater, or another updater running, or someone else probably won't accidently remove the downloaded item if the installer decides to 'own' it.

After the installer moves the downloaded item, it makes sure the item is not a symbolic link. If it is a non-regular file, the installer aborts, causing the updater to abort as well. Note this check is done after the move rather than before due to potential race conditions an attacker could create.

### Update Extraction
After the installer receives the input installation data, it starts extracting the update. The installer first sends a `SPUExtractionStarted` message.

If the unarchiver requires EdDSA validation before extraction (binary delta archives do) or if the expected installation type is a package type, then before starting the unarchiver, validation is checked to make sure the signature for the archive is valid. If the signature is not valid, then a `SPUArchiveExtractionFailed` message is sent to the updater (see below on what happens after that). We can't require validation before extracting for normal application updates because they allow changes to EdDSA keys. Delta updates are fine however because if those fail, then a full update can be tried.

After extraction starts, one or more `SPUExtractedArchiveWithProgress` messages indicating the unarchival progress are sent back to the updater. On failure, the installer will send `SPUArchiveExtractionFailed`. In the updater, if the update is a delta update and extraction fails, then the full archive is downloaded and we go back to the "Sending Installation Data" section to re-send the data and begin extraction again. If the update is not a delta update and extraction fails on the other hand, then the updater aborts causing the installer to abort as well.

### Post Validation
If the unarchiving succeeds, a `SPUValidationStarted` message is sent back to the updater, and the installer begins post validating the update.

If validation was already done before extraction, just the code signature is checked on the extracted bundle to make sure it's valid (if there's a code signature on the bundle). This is just a consistency check to make sure the developer didn't make a careless error.

If validation fails, the installer aborts, causing the updater to abort the update as well. Otherwise, the installer sends a message `SPUInstallationStartedStage1` to the updater and begins the installation.

### Retrieving Process Identifier

If the installer hasn't made a connection to the agent yet within the time threshold, the installer waits until a connection is made. Otherwise, the installer asks the agent for the process identifier of the application bundle that it wants to wait for termination. If the installer doesn't get a response within a certain threshold, the installer aborts.

When the installer gets the process identifier, it begins the installation. At this point on, the installer will try to perform the installation even if the connection to the updater or the connection to the agent invalidates.

### Starting the Installation

The installer figures out what kind of installer to use (regular, guided pkg, interactive pkg) based on the type of file inside the archive. If the type of file doesn't match the expected installation type from the input installation data, then the installer aborts causing the updater to abort as well.

Once the type of installer is found, the first stage of installation is performed:

* Regular application installer 1st stage: Makes sure this update is not a downgrade and do all initial installation work if possible (such as clearing quarantine, changing owner/group, updating modification date, invoking GateKeeper scan). This initial work is not done if the bundle has to transfer to another volume; in this case, this work will be done in a later stage.
* Guided Package installer 1st stage: Does nothing.
* Interactive Package installer (deprecated) 1st stage: Makes sure /usr/bin/open utility is available.

If the first stage fails, the installer aborts causing the updater to abort the update.

Otherwise a `SPUInstallationFinishedStage1` message is sent back to the updater along with some data. This data includes whether the application bundle to relaunch is currently terminated, and whether the installation at later stages can be performed silently (that is, with no user interaction allowed). If we reach here, only the interactive package installer can't be performed silently.

The installer then listens and waits for the target application to relaunch terminates. If it is already terminated, then it resumes to stage 2 and 3 of the installation immediately on the assumption that the installer does not have permission to show UI interaction to the user. Thus if the installer has to show user interaction here and hasn't received an OK from the updater (it won't if the target application is already terminated), the install will fail. If the target is already terminated, the installer will also assume that the target should not be relaunched after installation.

### Installation Waiting Period
The updater receives `SPUInstallationFinishedStage1` message. The updater sends a message `SPUSentUpdateAppcastItemData` with the appcast data in case the updater may request for it later (due to installer resumability, discussed later). It also reads if the target has already been terminated (implying that the installer will continue installing the update immediately), and if the installation will be done silently.

For UI based update drivers, the updater tells the user driver to show that the application is ready to be relaunched - the user can continue to install & relaunch the app. The user driver is only alerted however if the installation isn't happening immediately (that is, if the target application to relaunch is still alive). The user driver can decide whether to a) install b) install & relaunch or c) delay installation. If installation is delayed, it can be resumed later, or if the target application terminates, the installer will try to continue installation if it is capable to without user interaction.

For automatic based drivers, if the update is not going to be installed immediately and if it can be installed silently, the updater's delegate has a choice to handle the immediate installation of the update. If the delegate handles the installation, it can invoke a block that will trigger the automatic update driver to tell the installer to resume to stage 2 as detailed in step the "Continue to Installation" section - except without displaying any user interface and by relaunching the application afterwards. If the delegate handles the immediate installation, the automatic update driver will not abort, it will just leave the driver running until the installer requests for the app to be terminated later. This means the update can't be resumed later and the user driver won't be involved.

Otherwise if the updater delegate doesn't handle immediate installation for automatic based drivers (assuming still the update is not going to be installed immediately), the update driver is aborted; the installer will still wait for the target to terminate however. If the update cannot be silently installed or if the update is marked as critical from the appcast, the update procedure is actually 'resumed' as a scheduled UI based update driver immediately. The update driver can also be 'resumed' later when the user initiates for an update manually or when a long duration (I think a week) has passed by without the user terminating the application. Note automatic based drivers are unable to do a resume, so only UI based ones can.

If an update driver is resumed (which cannot happen if the target application is already terminated by the way), then the updater first requests the installer for the appcast item data that the installer received before. The updater does this by creating a temporary distinct connection for the purpose of querying for the installation status. The connection will give up if a short timeout passes. If the updater fails to retrieve resume data, it assumes that there's no update to resume and will start back from the beginning. The updater can use this data for showing release notes, etc. Note the updater and target application don't have to live in the same process, and the updater could choose to terminate and resume later as a new process - so having the installer keep the appcast item data is nice.

Afterwards the resumed update driver then allows the user driver to decide whether to a) install the update now, b) install & relaunch the update, or to c) delay the update installation and abort the update driver. Note we are now back to the same options discussed earlier.

### Continue to Installation
If the user driver decides to install the update, it sends a `SPUResumeInstallationToStage2` message to the installer and supplies whether the update should be relaunched, and whether user interface can be displayed. The user driver specifies that the user interface can be displayed as long as the updater delegate allows interaction. If the updater's delegate handles immediate installation in the automatic based update driver, UI cannot be displayed there too.

The installer receives `SPUResumeInstallationToStage2` and reads whether it should relaunch the target application and whether it can show UI (thus be allowed to show user interaction). The installer then resumes to stage 2 of the installation if it has not been performed already (that is if the target app already terminated). Note if the installer doesn't receive this message before the target application terminates, then the installer will not relaunch or show UI and resume stage 2 & 3 by itself. Again not displaying UI is only an issue for interactive based package installers which are deprecated.

If the 2nd stage succeeds, the installer sends a `SPUInstallationFinishedStage2` message back to the updater, including if the target application has already terminated at this time. If the target application has not already been terminated, the installer sends a request to the progress agent to *terminate* the application. By *terminate*, we mean sending an Apple quit event, allowing the application or user to possibly cancel or delay termination.

The updater receives a `SPUInstallationFinishedStage2` message, and reads if the target application had already been terminated. If the target application has not already terminated, the updater tells the user driver to show that the application is being sent a termination request.

In the case termination of the application is delayed or canceled, the user driver may re-try sending a `SPUResumeInstallationToStage2` message to the installer. This time the installer will recognize it already completed stage 2. If it hasn't proceeded onto stage 3 it will send another quit event to the application. This re-try can be done multiple times.

### Showing Progress

When the target application is terminated, if the updater allowed the installer to show UI progress and the installation type doesn't show progress on its own (only interactive package installer shows progress on its own), then the installer sends a `SPUUpdaterAlivePing` message to the updater. If the updater is still alive by now and receives the message, the updater will then send back a `SPUUpdaterAlivePong` message. This lets the installer know that the updater is still active after the target application is terminated, and whether the installer should later be responsible for displaying updater progress or not if a short time passes by, and the installation is still not finished. If the updater is still not alive, then the installer should be responsible for showing progress if otherwise allowed.

If the installer decides to show progress, it sends a message to the progress agent to show progress UI. Under most circumstances, the installation will finish faster than this point is reached however (exceptions may be guided package installers and updates over a remote network mount). If the connection to the updater is still connected after this short time passes (eg: like with sparkle-cli), then it's the updater's job to show progress instead.

### Finishing the Installation
The installer starts stage 3 of the installation after the target application is terminated as well. The third stage does the final installation for updating and replacing the new updated bundle.

If the third stage fails, then the installer aborts, causing the updater driver to abort if it's still running. The target application is not ever relaunched on failure.

Otherwise if the third stage succeeds, the installer sends a message to the agent to stop showing progress. The agent uses this hint to acknowledge that it should stop broadcasting the status info service for the updater. If the connection to the updater is still alive, a `SPUInstallationFinishedStage3` message is sent back to the updater and the updater driver silently aborts the update.

The installer then sends a message to the agent to relaunch the new application if the installer was requested to relaunch it. This also signals to the agent that it will terminate shortly. If the installer decides not to relaunch the update, the agent will terminate when its connection to the installer invalidates. The installer lastly does cleanup work by removing its update directory it was using and exits.

When the progress agent exits, it cleans up by removing itself from disk. The installer doesn't do that because the installer isn't copied to another location in the first place.

## Notes:

* Performing an update as the root user is not currently supported. The command line driver (minorly) and the agent application link to AppKit, and running the agent as a different user (i.e, dropping from root -> logged in user) is not particularly the most elegant idea.

* We use IPC in such a way that the installer process does not trust the updater process, which is why the installer does extraction, validation, and installation -- all in a single process. The launcher portion of code (which could be running as a XPC service) also does not trust the updater for determining the paths to the installer and agent tool. This portion of code does not check the code signing signature of the installer or agent though for reasons explained in the code.

* We have timeouts and ping/pong messages in various cases because we don't want to trust the other end very much for communicating back quickly. On older systems in my testing (eg: 10.8), connection invalidation events don't even get sent to the other end when interacting with launchd, possibly due a bug that is outputted in Console.app.

* When we terminate the application before doing final installation work, we send an Apple quit event to all running application instances we find under the agent's GUI login session. This does not include running instances from other logged in sessions -- that may require authenticating all the time, so trade off is not worthwhile. Also currently the installer only handles a single process identifier to watch for until termination, and certainly doesn't handle the case if more instances are launched afterwards. Note all of this only applies to instances being launched from the same bundle path, and the consequence may rarely be updating a bundle when a running instance is still left alive.

* SMJobBless() would be interesting to explore and perhaps more suitable for sparkle-cli than ordinary application updaters because using this API is less appropriate for one-off installations. Furthermore, the installer would have to change to persist rather than be a one-time install, and may have to handle multiple connections for installing multiple bundles simultaneously.
