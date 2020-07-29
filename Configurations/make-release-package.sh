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
    rm -f "Sparkle-$CURRENT_PROJECT_VERSION.tar.xz"

    mkdir -p "$CONFIGURATION_BUILD_DIR/staging"
    cp "$SRCROOT/CHANGELOG" "$SRCROOT/LICENSE" "$SRCROOT/Resources/SampleAppcast.xml" "$CONFIGURATION_BUILD_DIR/staging"
    cp -R "$SRCROOT/bin" "$CONFIGURATION_BUILD_DIR/staging"
    cp "$CONFIGURATION_BUILD_DIR/BinaryDelta" "$CONFIGURATION_BUILD_DIR/staging/bin"
    cp "$CONFIGURATION_BUILD_DIR/generate_appcast" "$CONFIGURATION_BUILD_DIR/staging/bin"
    cp "$CONFIGURATION_BUILD_DIR/generate_keys" "$CONFIGURATION_BUILD_DIR/staging/bin"
    cp "$CONFIGURATION_BUILD_DIR/sign_update" "$CONFIGURATION_BUILD_DIR/staging/bin"
    cp -R "$CONFIGURATION_BUILD_DIR/Sparkle Test App.app" "$CONFIGURATION_BUILD_DIR/staging"
    cp -R "$CONFIGURATION_BUILD_DIR/Sparkle.framework" "$CONFIGURATION_BUILD_DIR/staging"

    # Only copy dSYMs for Release builds, but don't check for the presence of the actual files
    # because missing dSYMs in a release build SHOULD trigger a build failure
    if [ "$CONFIGURATION" = "Release" ] ; then
        cp -R "$CONFIGURATION_BUILD_DIR/BinaryDelta.dSYM" "$CONFIGURATION_BUILD_DIR/staging/bin"
        cp -R "$CONFIGURATION_BUILD_DIR/generate_appcast.dSYM" "$CONFIGURATION_BUILD_DIR/staging/bin"
        cp -R "$CONFIGURATION_BUILD_DIR/generate_keys.dSYM" "$CONFIGURATION_BUILD_DIR/staging/bin"
        cp -R "$CONFIGURATION_BUILD_DIR/sign_update.dSYM" "$CONFIGURATION_BUILD_DIR/staging/bin"
        cp -R "$CONFIGURATION_BUILD_DIR/Sparkle Test App.app.dSYM" "$CONFIGURATION_BUILD_DIR/staging"
        cp -R "$CONFIGURATION_BUILD_DIR/Sparkle.framework.dSYM" "$CONFIGURATION_BUILD_DIR/staging"
    fi

    cd "$CONFIGURATION_BUILD_DIR/staging"
    # Sorted file list groups similar files together, which improves tar compression
    find . \! -type d | rev | sort | rev | tar cv --files-from=- | xz -9 > "../Sparkle-$CURRENT_PROJECT_VERSION.tar.xz"
    rm -rf "$CONFIGURATION_BUILD_DIR/staging"
    
    # Generate zip containing the xcframework for SPM
    cd "$CONFIGURATION_BUILD_DIR"
    rm -rf "Sparkle.xcarchive"
    zip -rqyX "Sparkle-SPM-$CURRENT_PROJECT_VERSION.zip" "Sparkle.xcframework"
    # Generate new Package manifest
    cp "$SRCROOT/Package-template.swift" "$CONFIGURATION_BUILD_DIR"
    mv "Package-template.swift" "Package.swift"
    # is equivalent to shasum -a 256 FILE
    spm_checksum=$(swift package compute-checksum "Sparkle-SPM-$CURRENT_PROJECT_VERSION.zip")
    rm -rf ".build"
    sed -i '' -e "s/VERSION_PLACEHOLDER/$CURRENT_PROJECT_VERSION/g" "Package.swift"
    sed -i '' -e "s/CHECKSUM_PLACEHOLDER/$spm_checksum/g" "Package.swift"
    cp "Package.swift" "$SRCROOT"
    echo "Package.swift updated with the following values:"
    echo "Version: $CURRENT_PROJECT_VERSION"
    echo "Checksum: $spm_checksum"
fi
