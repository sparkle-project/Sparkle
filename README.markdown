# Sparkle <img src="Resources/Sparkle.png" width=48 height=48 alt=""/>
is an easy-to-use software update framework for Cocoa developers.

## Changes since 1.5b

* Up-to-date with 10.10 SDK and Xcode 6. Supports OS X 10.7+.
* Cleaned up and modernized code, using ARC and Autolayout.
* Merged bugfixes, security fixes and some features from multiple Sparkle forks.
* Truly automatic background updates (no UI at all) when user agreed to "Automatically download and install updates in the future."
* Ability to mark updates as critical.
* Progress and status notifications for the host app.
* Name of finish_installation.app can be configured to match your app's name.

## Features

* True self-updating—no work required from the user.
* Displays release notes to the user via WebKit.
* Displays a detailed progress window to the user.
* Supports authentication for installing in secure locations.
* Really, really easy to install.
* Uses appcasts for release information.
* The user can choose to automatically download and install all updates.
* Seamless integration—there's no mention of Sparkle; your icons and app name are used.
* Supports Apple code signing and DSA signatures for ultra-secure updates.
* Sparkle requires no code in your app, so it's trivial to upgrade or remove the module.
* Optionally sends user demographic information to the server when checking for updates.
* Sparkle doesn't bug the user until second launch for better first impressions.
* Sparkle can install .pkg files for more complicated products.
* Supports bundles, preference panes, plugins, and other non-.app software.
* Supports branches due to minimum OS version requirements.
* Deep delegate support to make Sparkle work exactly as you need.
