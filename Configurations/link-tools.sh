#!/bin/sh

# Create symlinks to our helper tools in Sparkle framework bundle
# so URLForAuxiliaryExecutable: will pick up the tools. Doing this is supported in the Code Signing in Depth guide.

FRAMEWORK_PATH="${TARGET_BUILD_DIR}"/"${FULL_PRODUCT_NAME}"

ln -h -f -s "Versions/Current/""${SPARKLE_RELAUNCH_TOOL_NAME}" "${FRAMEWORK_PATH}"/"${SPARKLE_RELAUNCH_TOOL_NAME}"
ln -h -f -s "Versions/Current/""${SPARKLE_INSTALLER_PROGRESS_TOOL_NAME}".app "${FRAMEWORK_PATH}"/"${SPARKLE_INSTALLER_PROGRESS_TOOL_NAME}".app
