# Sparkle <img src="Resources/Sparkle.png" width=48 height=48 alt=""/>
is an easy-to-use software update framework for Cocoa developers.

[![Build Status](https://travis-ci.org/sparkle-project/Sparkle.svg?branch=master)](https://travis-ci.org/sparkle-project/Sparkle)

## Changes since 1.5b

* Up-to-date with 10.10 SDK and Xcode 6. Supports OS X 10.7+.
* Cleaned up and modernized code, using ARC and Autolayout.
* Merged bugfixes, security fixes and some features from multiple Sparkle forks.
* Truly automatic background updates (no UI at all) when user agreed to "Automatically download and install updates in the future."
* Ability to mark updates as critical.
* Progress and status notifications for the host app.
* Name of finish_installation.app can be configured to match your app's name.

## Features

* True self-updating—the user can choose to automatically download and install all updates.
* Displays a detailed progress window to the user.
* Supports authentication for installing in secure locations.
* Supports Apple code signing and DSA signatures for ultra-secure updates.
* Easy to install. Sparkle requires no code in your app, so it's trivial to upgrade or remove the framework.
* Uses appcasts for release information. Appcasts are supported by 3rd party update-tracking programs and websites.
* Displays release notes to the user via WebKit.
* Sparkle doesn't bug the user until second launch for better first impressions.
* Seamless integration—there's no mention of Sparkle; your icons and app name are used.
* Deep delegate support to make Sparkle work exactly as you need.
* Optionally sends system information to the server when checking for updates.
* Supports bundles, preference panes, plugins, and other non-.app software. Can install .pkg files for more complicated products.
* Supports branches due to minimum OS version requirements.
