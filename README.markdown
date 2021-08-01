# Sparkle 2 (Beta) ![Build Status](https://github.com/sparkle-project/Sparkle/workflows/Build%20%26%20Tests/badge.svg?branch=2.x) <a href="https://www.stackpath.com/?utm_source=sparkle-github&amp;utm_medium=badge&amp;utm_campaign=readme"><img src="https://img.shields.io/badge/sponsored%20by-StackPath-orange.svg" alt="sponsored by: StackPath"></a>

Secure and reliable software update framework for Cocoa developers.

<img src="Resources/Screenshot.png" width="732" alt="Sparkle shows familiar update window with release notes">

This is the upcoming new version of Sparkle.
Major new features are support for sandboxing, custom user interfaces, updating external bundles, and a more modern secure architecture which includes faster and more reliable installs.

For the production ready version of Sparkle, please see the [Sparkle 1.x (master) branch](https://github.com/sparkle-project/Sparkle/tree/master). Note development has shifted to Sparkle 2 and the 1.x branch is now only accepting bug fixes, localization updates, and adoption of critical upcoming OS features.

Sparkle 2 is currently in beta. Applications, typically sandboxed, have already been using it in production, but some work including testing is still required before an official version can be released. In the meantime, a nightly build can be downloaded by selecting a recent [workflow run](https://github.com/sparkle-project/Sparkle/actions?query=event%3Apush+is%3Asuccess+branch%3A2.x) and downloading the corresponding Sparkle-distribution artifact. The current status of Sparkle 2 is tracked in issue [#1523](https://github.com/sparkle-project/Sparkle/issues/1523).

If you can help with testing or reviewing over the new changes, please report issues or submit pull requests!

New issues should be [reported here](https://github.com/sparkle-project/Sparkle/issues). Internal design documents can be found in [Documentation](Documentation/).

Please visit [Sparkle's website](http://sparkle-project.org) for up to date documentation on using and migrating over to Sparkle 2. Refer to [Changelog](CHANGELOG) for a more detailed list of changes.

## Features

* Seamless. There's no mention of Sparkle; your icons and app name are used.
* Secure. Updates are verified using EdDSA signatures and Apple Code Signing.
* Fast. Supports delta updates which only patch files that have changed.
* Easy to install. Sparkle requires no code in your app, and only needs static files on a web server.
* Supports bundles, preference panes, plugins, and other non-.app software. Can install .pkg files for more complicated products.
* Handles permissions, quarantine and automatically asks for authentication if needed.
* Uses RSS-based appcasts for release information. Appcasts are a de-facto standard supported by 3rd party update-tracking programs and websites.
* Stays hidden until second launch for better first impressions.
* Truly self-updating — the user can choose to automatically download and install all updates in the background.
* Ability to mark updates as critical.
* Progress and status notifications for the host app.

## Requirements

* Runtime: macOS 10.11 or greater
* Build: Latest major Xcode (stable or beta, whichever is latest) and one major version less; at least Xcode 12 if using Swift Package Manager.
* HTTPS server for serving updates (see [App Transport Security](http://sparkle-project.org/documentation/app-transport-security/))

## Usage

See [getting started guide](https://sparkle-project.org/documentation/). No code is necessary, but a bit of Xcode configuration is required.

## Development

This repository uses git submodules, and will not build unless you clone recursively. Also, GitHub-provided ZIP/tar archives are broken due to GitHub not supporting git submodules properly.

    git clone https://github.com/sparkle-project/Sparkle
    git checkout 2.x
    git submodule update --init --recursive

### Troubleshooting

  * Please check **Console.app**. Sparkle prints detailed information there about all problems it encounters. It often also suggests solutions to the problems, so please read Sparkle's log messages carefully.

  * Use the `generate_appcast` tool which creates appcast files, correct signatures, and delta updates automatically.

  * Make sure the URL specified in [`SUFeedURL`](https://sparkle-project.org/documentation/customization/) is valid (typos/404s are a common error!), and that it uses modern TLS ([test it](https://www.ssllabs.com/ssltest/)).

  * Delete your app's preferences (in `~/Library/Preferences/<your bundle id>`) if you've set another feed URL programmatically via Sparkle's Objective-C interface.

### API symbols

Sparkle is built with `-fvisibility=hidden -fvisibility-inlines-hidden` which means no symbols are exported by default.
If you are adding a symbol to the public API you must decorate the declaration with the `SU_EXPORT` macro (grep the source code for examples).

### Building the distribution package

`cd` to the root of the Sparkle source tree and run `make release`. Sparkle-*VERSION*.tar.xz (or .bz2) will be created in a temporary directory and revealed in Finder after the build has completed.

Alternatively, build the Distribution scheme in the Xcode UI.

### Code of Conduct

We pledge to have an open and welcoming environment. See our [Code of Conduct](CODE_OF_CONDUCT.md).

## Project Sponsor

[StackPath](https://www.stackpath.com/?utm_source=sparkle-github&utm_medium=link&utm_campaign=readme-footer)
