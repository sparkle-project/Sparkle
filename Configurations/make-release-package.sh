#!/bin/bash
set -e

if [ "$ACTION" = "" ] ; then
    rm -rf "$CONFIGURATION_BUILD_DIR/staging"
    rm -f "Sparkle-$CURRENT_PROJECT_VERSION.zip"

    mkdir -p "$CONFIGURATION_BUILD_DIR/staging"
    cp "$SRCROOT/CHANGELOG" "$SRCROOT/LICENSE" "$SRCROOT/Resources/SampleAppcast.xml" "$CONFIGURATION_BUILD_DIR/staging"
    cp -R "$SRCROOT/bin" "$CONFIGURATION_BUILD_DIR/staging"
    cp "$CONFIGURATION_BUILD_DIR/BinaryDelta" "$CONFIGURATION_BUILD_DIR/staging/bin"
    cp -R "$CONFIGURATION_BUILD_DIR/Sparkle.framework" "$CONFIGURATION_BUILD_DIR/staging"
    cp -R "$CONFIGURATION_BUILD_DIR/Sparkle.framework.dSYM" "$CONFIGURATION_BUILD_DIR/staging"

    cd "$CONFIGURATION_BUILD_DIR/staging"
    zip --symlinks -r "../Sparkle-$CURRENT_PROJECT_VERSION.zip" .
    rm -rf "$CONFIGURATION_BUILD_DIR/staging"
fi
