# Sparkle [![Build Status](https://travis-ci.org/sparkle-project/Sparkle.svg?branch=master)](https://travis-ci.org/sparkle-project/Sparkle) <a href='https://app.ship.io/dashboard#/jobs/8814/history' target='_blank'><img src='https://app.ship.io/jobs/V3PoCLcN5ft5Pnq0/build_status.png' height='20' /></a> [![Coverage Status](https://coveralls.io/repos/sparkle-project/Sparkle/badge.svg?branch=master&service=github)](https://coveralls.io/github/sparkle-project/Sparkle?branch=master)

An easy-to-use software update framework for Cocoa developers.

## Important: About This Fork

This fork by Daniel Jalkut of Red Sweater Software deviates from the canonical sparkle-project repository in a few important ways:

* Rudimentary support for sandboxing is supported through the use of an XPC tool to kick off the install/relaunch process. (Courtesy tumult and wbyoung).
* Various changes to Sparkle.strings are made to (IMHO) lighten the tone of the language to be less excited and more professional.

**Do not use this code as is.**

The state of this project *right now* is "not tested." I have just on July 27, 2015 finished a merge with sparkle-project but have not yet tested that all the expected XPC-based stuff is working as expected. When the state of this project is once again "stable" I will update this readme to remove this line and replace it with something more encouraging. :)

**If you do use this code.**

If you decide to use this code and test its functionality etc., one caveat you should be aware of is that the XPC service is built with a "red sweater" based reverse domain style name. You probably want to change this to your own organization's ID namespace. Search the project for "com.red-sweater" to find any references along these lines.

<img src="Resources/Screenshot.png" width="715" alt="Sparkle shows familiar update window with release notes">

## Changes since 1.5b

* Up-to-date with 10.11 SDK and Xcode 7. Supports OS X 10.7+.
* Cleaned up and modernized code, using ARC and Autolayout.
* Merged bugfixes, security fixes and some features from multiple Sparkle forks.
* Truly automatic background updates (no UI at all) when user agreed to "Automatically download and install updates in the future."
* Ability to mark updates as critical.
* Progress and status notifications for the host app.
* Name of finish_installation.app can be configured to match your app's name.
* Upgraded and more reliable binary delta and code signing verification.

## Features

* True self-updating—the user can choose to automatically download and install all updates.
* Displays a detailed progress window to the user.
* Supports authentication for installing in secure locations.
* Supports Apple Code Signing and DSA signatures for ultra-secure updates.
* Easy to install. Sparkle requires no code in your app, so it's trivial to upgrade or remove the framework.
* Uses appcasts for release information. Appcasts are supported by 3rd party update-tracking programs and websites.
* Displays release notes to the user via WebKit.
* Sparkle doesn't bug the user until second launch for better first impressions.
* Seamless integration—there's no mention of Sparkle; your icons and app name are used.
* Deep delegate support to make Sparkle work exactly as you need.
* Optionally sends system information to the server when checking for updates.
* Supports bundles, preference panes, plugins, and other non-.app software. Can install .pkg files for more complicated products.
* Supports branches due to minimum OS version requirements.

## Developers

Building Sparkle requires Xcode 5 or above.

### API

Sparkle is built with `-fvisibility=hidden -fvisibility-inlines-hidden` which means no symbols are exported by default.
If you are adding a symbol to the public API you must decorate the declaration with the `SU_EXPORT` macro (grep the source code for examples).

### Building the distribution package

`cd` to the root of the Sparkle source tree and run `make release`. Sparkle-*VERSION*.tar.bz2 will be created in a temporary directory and revealed in Finder after the build has completed.

Alternatively, build the Distribution scheme in the Xcode UI.
