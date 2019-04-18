# Building

If release products have not already been built, they can be built by:

```
cd <path-to>/Sparkle/

make release
```

Upon success, a Finder window will open revealing an archive containing the newly-built Sparkle binaries. Expand the archive (e.g., to the Desktop).

Alternatively, you can build the "Distribution" scheme from within the Xcode project.

Debug builds of Sparkle can also be built from Xcode. Note that debug builds change Sparkle's default behavior to ease development. Never use a debug build of Sparkle for distribution.

# Installing

To install Sparkle, drag Sparkle.framework into your project as you would any other framework. Make sure you have a build phase to copy the framework into your application's Frameworks directory at build time.

# XPC Services and Embedded Applications

If your application is sandboxed, you will need to embed one or more of Sparkle's XPC services into your application. These are used to perform privileged operations that your sandboxed app, and the rest of the Sparkle framework, are not authorized to perform. Even if you are not strictly required to use a particular XPC service, there may still be some merit to separating privileges.

* `SparkleInstallerLauncher`, `SparkleInstallerConnection`, and `SparkleInstallerStatus`: These are required for most sandboxed apps, and are used by Sparkle to perform the privileged operations of upgrading your app, relaunching it, and reporting progress to the app as it proceeds.

* `SparkleDownloader`: This is required only if your sandboxed app does not already possess the "com.apple.security.network.client" entitlement, allowing it to make outgoing HTTP(S) connections. If you do decide to include the Downloader service and your app does not pass Apple's App Transport Security requirements, then you may have to add exceptions inside the downloader service's Info.plist.

Note: If your sandboxed app does not have the networking entitlement mentioned above, then linked release notes cannot contain external references (e.g.: images or external style sheets), because loading them will be prevented by the sandbox.

Apps that are not sandboxed may still want to embed the services if they need to code sign the services with their own signatures. The copies of these services within the built Sparkle framework will have the same signature as the framework.

If you want to code sign Sparkle's installer tools (Autoupdate and Updater.app), then you should include the SparkleInstallerLauncher XPC service even if your app is not sandboxed. Note that Sparkle keeps a copy of these tools inside the framework, because using the XPC services is optional, and they need to be inside the XPC service for security reasons. If you wish, you can remove them from the framework if you use the InstallerLauncher service.

If you code sign your application, these XPC services also need to be signed by you with the attached entitlements. Included is a script to automate this.

Here is an example of invoking the script with a Developer ID identity (replace `XXX` appropriately):

```
./bin/codesign_embedded_executable "Developer ID Application: XXX" XPCServices/*.xpc

./bin/codesign_embedded_executable "Developer ID Application: XXX" ./Sparkle.framework/Versions/A/Resources/Autoupdate

./bin/codesign_embedded_executable "Developer ID Application: XXX" ./Sparkle.framework/Versions/A/Resources/Updater.app/
```

After signing the executables, add them to the appropriate copy phases and link settings in the app target. Check the "Code Sign on Copy" option for the FW phase (it's not offered for the XPC copy phase).

Note that the `codesign_embedded_executable` script uses the hardened runtime option, so your app can be notarized ([required](https://developer.apple.com/documentation/security/notarizing_your_app_before_distribution?language=objc) for macOS 10.14.5 and higher).

# Testing

If you're not using the sandboxed version, you can just lower the `CURRENT_PROJECT_VERSION` in your app target below the latest version in your appcast, build & run from Xcode, and hit the Check for Updates… UI element.

For the sandboxed version, testing with a debug build running from Xcode doesn't work—the "Extracting Update" phase either hangs or fails. You'll have to do an Archive build and export a Developer ID-signed or notarized app.

# Known Issues

Search the [issues database](https://github.com/sparkle-project/Sparkle/issues) for bugs specific to the `ui-separation-and-xpc` branch.
