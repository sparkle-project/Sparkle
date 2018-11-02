== Building ==

If release products have not already been built, they can be built by:

> make release

Or build the "Distribution" scheme from within the Xcode project.

Debug builds of Sparkle can also be built from Xcode. Note that debug builds change Sparkle's default behavior to ease development. Never use a debug build of Sparkle for distribution.

== Installing ==

To install Sparkle, you can copy Sparkle.framework into your project as you would any other framework. Make sure you have a build phase to copy the framework into your application's Frameworks directory.

Sparkle has a few components that can optionally be handed off to XPC services. If you sandbox your application, you will need to use these.

If you have a sandboxed application and it has a "com.apple.security.network.client" entitlement to allow for outgoing HTTP connections, then the Downloader service is not necessary to include. If you do decide to include the Downloader service and your application does not pass Apple's App Transport Security requirements, then you may have to add exceptions inside the downloader service's Info.plist.

If you have a sandboxed application that does not have the entitlement mentioned above for allowing outgoing HTTP connections, then linked release notes cannot contain external references (eg: images or external style sheets).

If you want to code sign Sparkle's installer tools (Autoupdate and Updater.app), then you should include the InstallerLauncher XPC service regardless if you have a sandboxed application or not. Note Sparkle keeps a copy of these tools inside its framework's resources because using the XPC services is optional, and they need to be inside the XPC service for security reasons. If you wish, you can remove them from the framework if you use the InstallerLauncher service.

If you code sign your application, these XPC services will also need to be signed by you with the attached entitlements. Included is a script to automate this.

Here is an example of invoking the script with my Developer ID:
> ./bin/codesign_xpc "Developer ID Application" XPCServices/*.xpc

After signing the services, copy them into your project and set up a build phase to embed the XPC Services into your application.

Then test if your application works :).

== System Requirements ==

This version of Sparkle only supports running on macOS 10.8 and later

== Known Issues ==

https://github.com/zorgiepoo/sparkle-ui-xpc-issues/issues
