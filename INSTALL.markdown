# Building

If release products have not already been built, they can be built by:

> make release

Or build the "Distribution" scheme from within the Xcode project.

Debug builds of Sparkle can also be built from Xcode. Note that debug builds change Sparkle's default behavior to ease development. Never use a debug build of Sparkle for distribution.

# Installing

To install Sparkle, drag Sparkle.framework into your project as you would any other framework. Make sure you have a build phase to copy the framework into your application's Frameworks directory at build time.

# XPC Services

If your application is sandboxed, you will need to embed one or more of Sparkle's XPC services into your application. These are used to perform privileged operations that your sandboxed app, and the rest of the Sparkle framework, are not authorized to perform.

* `SparkleInstallerLauncher`: This is required for all sandboxed apps and is used by Sparkle to perform the privileged operation of upgrading your app and relaunching it.

* `SparkleDownloader`: This is required only if your sandboxed app does not already possess the "com.apple.security.network.client" entitlement, allowing it to make outgoing HTTP(S) connections. If you do decide to include the Downloader service and your app does not pass Apple's App Transport Security requirements, then you may have to add exceptions inside the downloader service's Info.plist.

Note: If your sandboxed app does not have the networking entitlement mentioned above, then linked release notes cannot contain external references (e.g.: images or external style sheets), because loading them will be prevented by the sandbox.

Apps that are not sandboxed may still want to embed the services if they need to code sign the services with their own signatures. The copies of these services within the built Sparkle framework will have the same signature as the framework.

If you want to code sign Sparkle's installer tools (Autoupdate and Updater.app), then you should include the SparkleInstallerLauncher XPC service even if your app is not sandboxed. Note that Sparkle keeps a copy of these tools inside the framework, because using the XPC services is optional, and they need to be inside the XPC service for security reasons. If you wish, you can remove them from the framework if you use the InstallerLauncher service.

If you code sign your application, these XPC services also need to be signed by you with the attached entitlements. Included is a script to automate this.

Here is an example of invoking the script with the default Developer ID identity:

> ./bin/codesign_xpc "Developer ID Application" XPCServices/*.xpc

After signing the services, drag them into your project and set up a build phase to embed the XPC Services into your application.

Then test if your application works :).

# Known Issues

https://github.com/zorgiepoo/sparkle-ui-xpc-issues/issues
