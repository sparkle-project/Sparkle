# Security

First, some references I've found to be quite useful:

* WWDC 2010 video on "Creating Secure Applications" - [asciiwwdc](http://asciiwwdc.com/2010/sessions/204?q=security).
* [EvenBetterAuthorizationExample](https://developer.apple.com/library/mac/samplecode/EvenBetterAuthorizationSample/Introduction/Intro.html) sample code by Apple for showing off privileged authorization as well as in sandboxed applications.
* Apple's [Daemons and Agents Technote](https://developer.apple.com/library/mac/technotes/tn2083/_index.html). Outdated and before XPC existed, but insightful.

Sparkle 2.0 puts a huge emphasis on splitting Sparkle into several components to achieve privilege separation.

* User Driver (Application; AppKit permitted)
* Updater Scheduler (Framework)
* XPC Services (Instead of some portions of Framework)
* Progress Agent (Application; AppKit permitted)
* Installer (Agent and Daemon safe)

These achieve privilege separation, because at least theoretically, they can all be placed into different processes from one another, although in practice the user driver and updater framework will likely be in the same process.

For XPC Services, it's significant to understand they can be used independent of sandboxing (although I wouldn't recommend this personally). Besides privilege separation, they also have an impact on fault tolerance and termination.

We have code that detects whether or not XPC services are available and enabled by the main application bundle. This is simpler and more efficient than attempting to create a connection and wait for a timeout. We don't have *any* checks for seeing if the "current process" is sandboxed; doing so is a rather broken behavior. The XPC Services are important, not the sandboxing.

I said above that XPC services are looked up in the main bundle. One may think this assumption doesn't hold for helpers or plug-ins inside applications. My response to that is they probably don't need the services, and they probably shouldn't be injecting Sparkle inside the host application anyway due to unintended conflicts and other consequences. A more appropriate approach may be to bundle a separate tool such as the sparkle command line utility.

The `InstallerLauncher` XPC service needs a `JoinExistingSession` key set to `YES` otherwise authorization will not work properly, and even less so on older systems. It took me forever to debug this, so it's worth mentioning.

When developing Sparkle 2.0, I still had a huge hole in the privilege separation even after supporting XPC Services and sandboxing. I fixed that by removing references to `AuthorizationExecuteWithPrivileges` and submitting a launchd agent/daemon for the installer. This is overlooked, but absolutely essential for our model to be secure.

When communicating to a launchd job, we've several options to use for IPC such as BSD Sockets, Mach ports, XPC (note: XPC is an IPC API and is != "XPC Services"), and file IO. The technote I linked above describes why Mach ports have user namespace issues and why BSD sockets may be preferred over them. However, now, XPC which allows you to choose which domain to look up is the simplest, best, and most modern choice. It's crucial in any event we don't have a daemon (running in system domain) try to *connect* to something in the user domain. Our launchd tasks should also be connected to rather than the other way around. As for communication via file IO, I just wouldn't go anywhere close to trusting such a model mixing in system and user running processes.

For sending Obj-C objects across the wire, we use `SPUSecureCoding` because Cocoa doesn't support sending objects securely out of the box unless working with XPC Services. It's very important the objects implement `NSSecureCoding` and whitelist types that are expected to be decoded, as well as whitelist types inside collections before decoding them.

The installer handles extraction, validation, and installation of the update. This was the main reason why other sandboxed-capable forks were rejected from being secure. The point to be stressed anyway is that these all need to be done in the same process; they can't be handed off by some other process. This is also why removing references to `AuthorizationExecuteWithPrivileges` is crucial as well.

Note that the installer does *not* handle downloading. That is handled by the updater framework. This is ideal because downloading can be done without disrupting the user, allowing it to be done silently without presenting an authorization dialog. The downloading portion of code can also be stuck into a XPC service with just an entitlement for allowing incoming connections. This also means for secure installations the installer cannot know (or trust) what protocol the update was downloaded from (i.e: http vs https). A good installer will not care, which is why applying updates without a EdDSA signature/key is now deprecated (reminder that Apple's code signature checks are not intended for complete integrity).
