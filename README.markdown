# Sparkle [![Build Status](https://travis-ci.org/sparkle-project/Sparkle.svg?branch=master)](https://travis-ci.org/sparkle-project/Sparkle) [![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage) [![CocoaPods](https://img.shields.io/cocoapods/v/Sparkle.svg?maxAge=2592000)]() <a href="https://www.stackpath.com/?utm_source=sparkle-github&amp;utm_medium=badge&amp;utm_campaign=readme"><img src="https://img.shields.io/badge/sponsored%20by-StackPath-orange.svg" alt="sponsored by: StackPath"></a>

Secure and reliable software update framework for Cocoa developers.

<img src="Resources/Screenshot.png" width="732" alt="Sparkle shows familiar update window with release notes">

## Features

* Seamless. There's no mention of Sparkle; your icons and app name are used.
* Secure. Updates are verified using DSA signatures and Apple Code Signing.
* Fast. Supports delta updates which only patch files that have changed.
* Easy to install. Sparkle requires no code in your app, and only needs static files on a web server.
* Supports bundles, preference panes, plugins, and other non-.app software. Can install .pkg files for more complicated products.
* Handles permissions, quarantine and automatically asks for authentication if needed.
* Uses RSS-based appcasts for release information. Appcasts are a de-facto standard supported by 3rd party update-tracking programs and websites.
* Sparkle stays hidden until second launch for better first impressions.
* Truly self-updating — the user can choose to automatically download and install all updates in the background.

## Changes since 1.5b

* Compatibilty with macOS Sierra.
* Up-to-date with 10.12 SDK and Xcode 8 (supports macOS 10.7+).
* Important security fixes.
* Cleaned up and modernized code, using ARC and Autolayout.
* Truly automatic background updates (no UI at all) when user agreed to "Automatically download and install updates in the future."
* Upgraded and more reliable binary delta and code signing verification.
* Ability to mark updates as critical.
* Progress and status notifications for the host app.

## Requirements

* Runtime: macOS 10.7 or greater
* Build: Xcode 7 and 10.8 SDK or greater
* HTTPS server for serving updates (see [App Transport Security](http://sparkle-project.org/documentation/app-transport-security/))

## Usage

See [getting started guide](https://sparkle-project.org/documentation/). No code is necessary, but a bit of Xcode configuration is required.

## Development

### API symbols

Sparkle is built with `-fvisibility=hidden -fvisibility-inlines-hidden` which means no symbols are exported by default.
If you are adding a symbol to the public API you must decorate the declaration with the `SU_EXPORT` macro (grep the source code for examples).

### Building the distribution package

`cd` to the root of the Sparkle source tree and run `make release`. Sparkle-*VERSION*.tar.bz2 will be created in a temporary directory and revealed in Finder after the build has completed.

Alternatively, build the Distribution scheme in the Xcode UI.

### Code of Conduct

We pledge to have an open and welcoming environment. See our [Code of Conduct](CODE_OF_CONDUCT.md).

## Project Sponsor

[StackPath](https://www.stackpath.com/?utm_source=sparkle-github&utm_medium=link&utm_campaign=readme-footer)
