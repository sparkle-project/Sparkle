#!/bin/bash
set -e

if [ "$ACTION" = "" ] ; then
    # If using cocoapods, sanity check that the Podspec version matches the Sparkle version
    if [ -x "$(command -v pod)" ]; then
        spec_version=$(printf "require 'cocoapods'\nspec = %s\nprint spec.version" "$(cat "$SRCROOT/Sparkle.podspec")" | LANG=en_US.UTF-8 ruby)
        if [ "$spec_version" != "$CURRENT_PROJECT_VERSION" ] ; then
            echo "podspec version '$spec_version' does not match the current project version '$CURRENT_PROJECT_VERSION'" >&2
            exit 1
        fi
    fi

    rm -rf "$CONFIGURATION_BUILD_DIR/staging"
    rm -rf "$CONFIGURATION_BUILD_DIR/staging-spm"
    rm -f "Sparkle-$CURRENT_PROJECT_VERSION.tar.xz"
    rm -f "Sparkle-$CURRENT_PROJECT_VERSION.tar.bz2"
    rm -f "Sparkle-for-Swift-Package-Manager.zip"

    mkdir -p "$CONFIGURATION_BUILD_DIR/staging"
    mkdir -p "$CONFIGURATION_BUILD_DIR/staging-spm"
    cp "$SRCROOT/CHANGELOG" "$SRCROOT/LICENSE" "$SRCROOT/INSTALL" "$SRCROOT/Resources/SampleAppcast.xml" "$CONFIGURATION_BUILD_DIR/staging"
    cp "$SRCROOT/CHANGELOG" "$SRCROOT/LICENSE" "$SRCROOT/INSTALL" "$SRCROOT/Resources/SampleAppcast.xml" "$CONFIGURATION_BUILD_DIR/staging-spm"
    cp -R "$SRCROOT/bin" "$CONFIGURATION_BUILD_DIR/staging"
    cp "$CONFIGURATION_BUILD_DIR/BinaryDelta" "$CONFIGURATION_BUILD_DIR/staging/bin"
    cp "$CONFIGURATION_BUILD_DIR/generate_appcast" "$CONFIGURATION_BUILD_DIR/staging/bin"
    cp "$CONFIGURATION_BUILD_DIR/generate_keys" "$CONFIGURATION_BUILD_DIR/staging/bin"
    cp "$CONFIGURATION_BUILD_DIR/sign_update" "$CONFIGURATION_BUILD_DIR/staging/bin"
    cp -R "$CONFIGURATION_BUILD_DIR/Sparkle Test App.app" "$CONFIGURATION_BUILD_DIR/staging"
    cp -R "$CONFIGURATION_BUILD_DIR/Sparkle Test App.app" "$CONFIGURATION_BUILD_DIR/staging-spm"
    cp -R "$CONFIGURATION_BUILD_DIR/sparkle.app" "$CONFIGURATION_BUILD_DIR/staging"
    cp -R "$CONFIGURATION_BUILD_DIR/sparkle.app" "$CONFIGURATION_BUILD_DIR/staging-spm"
    cp -R "$CONFIGURATION_BUILD_DIR/Sparkle.framework" "$CONFIGURATION_BUILD_DIR/staging"
    cp -R "$CONFIGURATION_BUILD_DIR/Sparkle.xcframework" "$CONFIGURATION_BUILD_DIR/staging-spm"
    cp -R "$CONFIGURATION_BUILD_DIR/SparkleCore.framework" "$CONFIGURATION_BUILD_DIR/staging"
    cp -R "$CONFIGURATION_BUILD_DIR/SparkleCore.xcframework" "$CONFIGURATION_BUILD_DIR/staging-spm"

    mkdir -p "$CONFIGURATION_BUILD_DIR/staging/XPCServices"

    cp -R "$CONFIGURATION_BUILD_DIR/$INSTALLER_LAUNCHER_BUNDLE_ID.xpc" "$CONFIGURATION_BUILD_DIR/staging/XPCServices"
    cp -R "$CONFIGURATION_BUILD_DIR/$DOWNLOADER_BUNDLE_ID.xpc" "$CONFIGURATION_BUILD_DIR/staging/XPCServices"
    cp -R "$CONFIGURATION_BUILD_DIR/$INSTALLER_CONNECTION_BUNDLE_ID.xpc" "$CONFIGURATION_BUILD_DIR/staging/XPCServices"
    cp -R "$CONFIGURATION_BUILD_DIR/$INSTALLER_STATUS_BUNDLE_ID.xpc" "$CONFIGURATION_BUILD_DIR/staging/XPCServices"

    cp "$SRCROOT/Downloader/$DOWNLOADER_BUNDLE_ID.entitlements" "$CONFIGURATION_BUILD_DIR/staging/XPCServices"

    # Only copy dSYMs for Release builds, but don't check for the presence of the actual files
    # because missing dSYMs in a release build SHOULD trigger a build failure
    if [ "$CONFIGURATION" = "Release" ] ; then
        cp -R "$CONFIGURATION_BUILD_DIR/BinaryDelta.dSYM" "$CONFIGURATION_BUILD_DIR/staging/bin"
        cp -R "$CONFIGURATION_BUILD_DIR/generate_appcast.dSYM" "$CONFIGURATION_BUILD_DIR/staging/bin"
        cp -R "$CONFIGURATION_BUILD_DIR/generate_keys.dSYM" "$CONFIGURATION_BUILD_DIR/staging/bin"
        cp -R "$CONFIGURATION_BUILD_DIR/sign_update.dSYM" "$CONFIGURATION_BUILD_DIR/staging/bin"
        cp -R "$CONFIGURATION_BUILD_DIR/Sparkle Test App.app.dSYM" "$CONFIGURATION_BUILD_DIR/staging"
        cp -R "$CONFIGURATION_BUILD_DIR/Sparkle Test App.app.dSYM" "$CONFIGURATION_BUILD_DIR/staging-spm"
        cp -R "$CONFIGURATION_BUILD_DIR/sparkle.app.dSYM" "$CONFIGURATION_BUILD_DIR/staging"
        cp -R "$CONFIGURATION_BUILD_DIR/sparkle.app.dSYM" "$CONFIGURATION_BUILD_DIR/staging-spm"
        cp -R "$CONFIGURATION_BUILD_DIR/Sparkle.framework.dSYM" "$CONFIGURATION_BUILD_DIR/staging"
        cp -R "$CONFIGURATION_BUILD_DIR/SparkleCore.framework.dSYM" "$CONFIGURATION_BUILD_DIR/staging"

        cp -R "$CONFIGURATION_BUILD_DIR/$INSTALLER_LAUNCHER_BUNDLE_ID.xpc.dSYM" "$CONFIGURATION_BUILD_DIR/staging/XPCServices"
        cp -R "$CONFIGURATION_BUILD_DIR/$DOWNLOADER_BUNDLE_ID.xpc.dSYM" "$CONFIGURATION_BUILD_DIR/staging/XPCServices"
        cp -R "$CONFIGURATION_BUILD_DIR/$INSTALLER_CONNECTION_BUNDLE_ID.xpc.dSYM" "$CONFIGURATION_BUILD_DIR/staging/XPCServices"
        cp -R "$CONFIGURATION_BUILD_DIR/$INSTALLER_STATUS_BUNDLE_ID.xpc.dSYM" "$CONFIGURATION_BUILD_DIR/staging/XPCServices"
    fi
    cp -R "$CONFIGURATION_BUILD_DIR/staging/bin" "$CONFIGURATION_BUILD_DIR/staging-spm"
    cp -R "$CONFIGURATION_BUILD_DIR/staging/XPCServices" "$CONFIGURATION_BUILD_DIR/staging-spm"

    cd "$CONFIGURATION_BUILD_DIR/staging"
    
    if [ -x "$(command -v xz)" ]; then
        XZ_EXISTS=1
    else
        XZ_EXISTS=0
    fi
    
    rm -rf "/tmp/sparkle-extract"
    mkdir -p "/tmp/sparkle-extract"

    # Sorted file list groups similar files together, which improves tar compression
    if [ "$XZ_EXISTS" -eq 1 ] ; then
        find . \! -type d | rev | sort | rev | tar cv --files-from=- | xz -9 > "../Sparkle-$CURRENT_PROJECT_VERSION.tar.xz"

        # Copy archived distribution for CI
        cp -f "../Sparkle-$CURRENT_PROJECT_VERSION.tar.xz" "../sparkle-dist.tar.xz"

        # Extract archive for testing binary validity
        tar -xf "../Sparkle-$CURRENT_PROJECT_VERSION.tar.xz" -C "/tmp/sparkle-extract"
    else
        # Fallback to bz2 compression if xz utility is not available
        find . \! -type d | rev | sort | rev | tar cjvf "../Sparkle-$CURRENT_PROJECT_VERSION.tar.bz2" --files-from=-

        # Extract archive for testing binary validity
        tar -xf "../Sparkle-$CURRENT_PROJECT_VERSION.tar.bz2" -C "/tmp/sparkle-extract"
    fi

    # Test code signing validity of the extracted products
    # This guards against our archives being corrupt / created incorrectly
    codesign --verify -vvv --deep "/tmp/sparkle-extract/Sparkle.framework"
    codesign --verify -vvv --deep "/tmp/sparkle-extract/SparkleCore.framework"
    codesign --verify -vvv --deep "/tmp/sparkle-extract/XPCServices/org.sparkle-project.Downloader.xpc"
    codesign --verify -vvv --deep "/tmp/sparkle-extract/XPCServices/org.sparkle-project.InstallerConnection.xpc"
    codesign --verify -vvv --deep "/tmp/sparkle-extract/XPCServices/org.sparkle-project.InstallerLauncher.xpc"
    codesign --verify -vvv --deep "/tmp/sparkle-extract/XPCServices/org.sparkle-project.InstallerStatus.xpc"
    codesign --verify -vvv --deep "/tmp/sparkle-extract/sparkle.app"
    codesign --verify -vvv --deep "/tmp/sparkle-extract/Sparkle Test App.app"
    codesign --verify -vvv --deep "/tmp/sparkle-extract/bin/BinaryDelta"
    codesign --verify -vvv --deep "/tmp/sparkle-extract/bin/generate_appcast"
    codesign --verify -vvv --deep "/tmp/sparkle-extract/bin/sign_update"
    codesign --verify -vvv --deep "/tmp/sparkle-extract/bin/generate_keys"

    rm -rf "/tmp/sparkle-extract"
    rm -rf "$CONFIGURATION_BUILD_DIR/staging"
    
    # Generate zip containing the xcframework for SPM
    cd "$CONFIGURATION_BUILD_DIR/staging-spm"
    #rm -rf "$CONFIGURATION_BUILD_DIR/Sparkle.xcarchive"
    zip -rqyX -9 "../Sparkle-for-Swift-Package-Manager.zip" *
    
    # GitHub actions set the CI environment variable to true
    if [ "$CI" != true ]; then
        # Get latest git tag
        cd "$SRCROOT"
        latest_git_tag=$(git describe --tags --abbrev=0)
        # Check semantic versioning
        if [[ $latest_git_tag =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)(\.(0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*))?(\\+([0-9a-zA-Z-]+(\.[0-9a-zA-Z-]+)*))?$ ]]; then
            echo "Tag $latest_git_tag follows semantic versioning"
        else
            echo "ERROR: Tag $latest_git_tag does not follow semantic versioning! SPM will not be able to resolve the repository" >&2
            exit 1
        fi
    else
        # Dummy placeholder for CI test builds as we don't really need to update Package.swift for building and testing purposes
        latest_git_tag="CI_BUILD"
    fi
    # Generate new Package manifest
    cd "$CONFIGURATION_BUILD_DIR"
    cp "$SRCROOT/Package.swift" "$CONFIGURATION_BUILD_DIR"
    if [ "$XCODE_VERSION_MAJOR" -ge "1200" ]; then
        # is equivalent to shasum -a 256 FILE
        spm_checksum=$(swift package compute-checksum "Sparkle-for-Swift-Package-Manager.zip")
        rm -rf ".build"
        sed -E -i '' -e "/let tag/ s/\".+\"/\"$latest_git_tag\"/" -e "/let version/ s/\".+\"/\"$CURRENT_PROJECT_VERSION\"/" -e "/let checksum/ s/[[:xdigit:]]{64}/$spm_checksum/" "Package.swift"
        cp "Package.swift" "$SRCROOT"
        echo "Package.swift updated with the following values:"
        echo "Version: $CURRENT_PROJECT_VERSION"
        echo "Tag: $latest_git_tag"
        echo "Checksum: $spm_checksum"
    else
        echo "warning: Xcode version $XCODE_VERSION_ACTUAL does not support computing checksums for Swift Packages. Please update the Package manifest manually."
    fi
    
    if [ "$XZ_EXISTS" -eq 1 ] ; then
        echo "WARNING: xz compression is used for official releases but bz2 is being used instead because xz tool is not installed on your system."
    fi
        
    rm -rf "$CONFIGURATION_BUILD_DIR/staging-spm"
fi
