#!/bin/sh

# If Carthage is trying to build us, it won't preserve code signing information from our bundled tools properly
# Building Sparkle from source with Carthage is thus not supported
if [ "$CARTHAGE" = "YES" ]; then
    echo "Error: Building Sparkle from source using Carthage is not supported. Please visit https://sparkle-project.org/documentation/ for proper Carthage integration."
    exit 1
fi

# Create symlinks to our helper tools in Sparkle framework bundle
# so URLForAuxiliaryExecutable: will pick up the tools. Doing this is supported in the Code Signing in Depth guide.

FRAMEWORK_PATH="${TARGET_BUILD_DIR}"/"${FULL_PRODUCT_NAME}"

ln -h -f -s "Versions/Current/""${SPARKLE_RELAUNCH_TOOL_NAME}" "${FRAMEWORK_PATH}"/"${SPARKLE_RELAUNCH_TOOL_NAME}"
ln -h -f -s "Versions/Current/""${SPARKLE_INSTALLER_PROGRESS_TOOL_NAME}".app "${FRAMEWORK_PATH}"/"${SPARKLE_INSTALLER_PROGRESS_TOOL_NAME}".app
