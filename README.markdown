# Sparkle-XPC-UI

A major fork to the popular Sparkle update framework that supports sandboxing, custom user interfaces, updating other bundles, and a modern secure architecture.

<img src="Resources/Screenshot.png" width="732" alt="Sparkle shows familiar update window with release notes">

This fork's current status is beta. I am no longer looking into adding or rewriting major functionality, and would like to finalize and have it be battle tested.

New issues that are found should be [reported here](https://github.com/zorgiepoo/sparkle-ui-xpc-issues/issues), and internal design documents can be found in `Documentation`. Discussion of this fork can be found on the [official branch](https://github.com/sparkle-project/Sparkle/issues/363).

# Features

## Sandboxing

This fork includes several XPC services that are generally optional to include in your application, but are required for sandboxed applications. See the `INSTALL` file for more detail.

When sandboxed, linked release notes are allowed. External references inside the linked release notes are only allowed if the host application has an incoming network entitlement. Lastly, updates can still be extracted from DMG files just as they are in the official branch.

## Custom User Interfaces

<img src="Resources/Screenshot2.png" width="350" alt="Sparkle shows a custom update window with release notes">

See the `SPUUserDriver` protocol and classes that implement it for how to write your own user interface. This enables extensibility of Sparkle without altering or extending internal classes.

Hold shift when launching the `Sparkle Test App` to try out the experimental user interface shown above (note: this custom interface requires running macOS 10.10 or later).

## Command Line Tool

<img src="Resources/Screenshot3.png" width="400" alt="Sparkle shows command line interface to installing updates">

The `sparkle` command line tool can be used to update any Sparkle supported bundle. `sparkle` is a great demonstration of updating other bundles, though that aspect is not limited to just this tool!

This utility may also be an ideal choice for plug-ins where loading a copy of Sparkle's framework into a host's application may lead to conflicts or have undesirable consequences.

## Modern Security

Not only is sandboxing supported, but launchd is now used for submitting the installer. XPC is used to communicate to the launchd job. Uses of `AuthorizationExecuteWithPrivileges`, which is neither secure or reliable, have been removed. Installation on standard user accounts has been tested heavily rather than being treated as an edge case.

Extraction, validation, and installation of the update are all handled by the installer. The XPC services and the installer job don't implicitly trust the other end of the connection. Signing downloads with a DSA signature is now encouraged more aggressively.

Usage of AppKit has been minimized greatly. No linkage of it is found in the installer daemon. All code core to Sparkle's functionality prevents it from being imported. Only user driver classes and a progress agent may use AppKit for showing UI. A `SparkleCore.framework` target has been created that just uses the core.

## API Compatibility

Despite decoupling update scheduling, UI, installation, and minimizing AppKit usage, a great deal of effort was made to maintain ABI compatibility with older versions of Sparkle. A deprecated `SUUpdater` shim exists for maintaining runtime compatibility. Please check out `SPUStandardUpdaterController` and `SPUUpdater` instead for modern replacements.

Interactive package based installations have been deprecated in favor for guided package installations. As a consequence, interactive installations now have to be opted into (eg: `foo.sparkle_interactive.pkg`). A `sparkle:installationType=package` or `sparkle:installationType=interactive-package` tag is also now required in the appcast enclosure item for package based installs.

No attempt is made to preserve compatibility with regards to subclassing Sparkle's internal classes. Doing this is not supported or maintainable anymore. Much of this desire will go away with the extensibility provided by the user driver API.

New Sparkle classes are now prefixed with `SPU` rather than `SU`. Older classes still use the `SU` prefix to maintain compatibility.

## Misc. Changes

* Updates are more instant to install once extracted. The "installing update" dialog seldomly shows up after the old application quits.
* The installer will attempt installing the update after extraction is finished, even if the user quits the process and doesn't relaunch the application explicitly.
* Updates can be downloaded in the background automatically (if enabled) and be resumed by the user later, even if the user has insufficent permission to install them initially.
* Authentication now occurs before launching the installer and before terminating the application, which can be canceled by the user cleanly.
* Sudden termination for silent updates isn't disabled because Sparkle doesn't listen for AppKit events anymore such as termination or power off (note the installer running as a separate process listens for termination).
* Distributing updates without DSA signing the archives is now deprecated.
* Sparkle's icon in the official branch is no longer used for installation. Instead, the icon of the bundle to update is used. A 32x32 image representation of the icon is needed for the authorization dialog.
* Delegation methods may have been removed or added to the newer updater API. Please review `SPUUpdaterDelegate` if using `SPUUpdater`.

## Requirements

* Runtime: **macOS 10.8** or greater (this has been bumped up!)
* Build: Not sure. I have been using Xcode 7.
* HTTPS server for serving updates (see [App Transport Security](http://sparkle-project.org/documentation/app-transport-security/))

## API Visibility

Sparkle is built with `-fvisibility=hidden -fvisibility-inlines-hidden` which means no symbols are exported by default.
If you are adding a symbol to the public API you must decorate the declaration with the `SU_EXPORT` macro (grep the source code for examples).

## Building the distribution package

`cd` to the root of the Sparkle source tree and run `make release`. Sparkle-*VERSION*.tar.bz2 will be created in a temporary directory and revealed in Finder after the build has completed.

Alternatively, build the Distribution scheme in the Xcode UI.

See the `INSTALL` file after building Sparkle, especially if interested in sandboxing support. The XPC services are not required for non-sandboxed applications.

## Code of Conduct

We pledge to have an open and welcoming environment. See our [Code of Conduct](CODE_OF_CONDUCT.md).

## Project Sponsor

[StackPath](https://www.stackpath.com/?utm_source=sparkle-github&utm_medium=link&utm_campaign=readme-footer)
